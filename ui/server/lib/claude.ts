// Spawn `claude -p "<phrase>"` subprocess. The phrase MUST be validated
// against the trigger allowlist by the caller BEFORE invoking this. This
// module enforces the allowlist again as defense in depth and is the only
// place in the codebase that calls child_process.spawn for the claude CLI.
import { spawn } from 'node:child_process';
import { isPhraseAllowed } from '../trigger-allowlist.js';
import { repoRoot } from './paths.js';

export interface ClaudeRunResult {
  exitCode: number;
  stdout: string;
  stderr: string;
  durationMs: number;
}

export interface ClaudeRunOptions {
  /** Max wall-clock duration before the subprocess is killed. Default: 5 minutes. */
  timeoutMs?: number;
}

/**
 * Run `claude -p "<phrase>"` and capture stdout/stderr. Returns the result
 * synchronously after the subprocess exits (or after the timeout, in which
 * case the subprocess is killed and exitCode is -1).
 *
 * SECURITY:
 * - Uses array-argument form with shell:false. The phrase is passed as a
 *   single argv element, never interpolated into a shell command line.
 * - Re-validates against the allowlist as defense-in-depth.
 * - cwd is locked to the repo root so the `claude` CLI discovers the
 *   `.claude/agents/` directory.
 * - Environment is MINIMAL — only the Windows + Node basics the CLI needs
 *   to find PATH, user profile, temp dirs, and Anthropic-stored credentials
 *   (which the CLI keeps under %APPDATA% / %LOCALAPPDATA%). The parent's
 *   full env is NOT inherited, so any sensitive variables set in the shell
 *   the operator launched start-ui.ps1 from do not leak into the subprocess.
 */
const SUBPROCESS_ENV_KEYS = [
  'PATH', 'PATHEXT',
  'USERPROFILE', 'HOMEDRIVE', 'HOMEPATH',
  'APPDATA', 'LOCALAPPDATA',
  'TEMP', 'TMP',
  'SystemRoot', 'SystemDrive', 'ComSpec',
  'USERNAME', 'USERDOMAIN',
] as const;

function minimalEnv(): NodeJS.ProcessEnv {
  const out: NodeJS.ProcessEnv = {};
  for (const k of SUBPROCESS_ENV_KEYS) {
    const v = process.env[k];
    if (v !== undefined) out[k] = v;
  }
  return out;
}
export async function runClaude(phrase: string, opts: ClaudeRunOptions = {}): Promise<ClaudeRunResult> {
  if (!isPhraseAllowed(phrase)) {
    throw new Error(`Trigger phrase rejected by allowlist: ${JSON.stringify(phrase)}`);
  }
  const timeoutMs = opts.timeoutMs ?? 5 * 60 * 1000;
  const started = Date.now();

  return await new Promise<ClaudeRunResult>((resolve) => {
    let stdout = '';
    let stderr = '';
    let killed = false;

    // shell: false is critical. With shell: true the phrase string would be
    // re-parsed by cmd.exe and any shell metacharacter we missed in
    // isPhraseAllowed could become an injection vector.
    const child = spawn('claude', ['-p', phrase], {
      cwd: repoRoot(),
      shell: false,
      windowsHide: true,
      stdio: ['ignore', 'pipe', 'pipe'],
      env: minimalEnv(),
    });

    const timer = setTimeout(() => {
      killed = true;
      try {
        child.kill('SIGTERM');
        setTimeout(() => {
          if (!child.killed) child.kill('SIGKILL');
        }, 5000);
      } catch {
        // best-effort
      }
    }, timeoutMs);

    child.stdout?.on('data', (chunk: Buffer) => { stdout += chunk.toString('utf8'); });
    child.stderr?.on('data', (chunk: Buffer) => { stderr += chunk.toString('utf8'); });

    child.on('error', (err) => {
      clearTimeout(timer);
      resolve({
        exitCode: -1,
        stdout,
        stderr: stderr + `\n[spawn error] ${err.message}`,
        durationMs: Date.now() - started,
      });
    });

    child.on('exit', (code) => {
      clearTimeout(timer);
      resolve({
        exitCode: killed ? -1 : (code ?? -1),
        stdout,
        stderr: killed ? stderr + '\n[killed: timeout exceeded]' : stderr,
        durationMs: Date.now() - started,
      });
    });
  });
}
