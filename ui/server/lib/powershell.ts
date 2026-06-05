// Spawn `powershell.exe` for the diagnostics endpoints that need to read
// Windows-specific state (scheduled tasks). Like claude.ts, this module is
// the single chokepoint for PowerShell subprocess invocations; the commands
// allowed here are hardcoded — no user-supplied PowerShell strings ever
// reach this layer.
import { spawn } from 'node:child_process';
import path from 'node:path';
import { repoRoot } from './paths.js';

export interface PSResult {
  exitCode: number;
  stdout: string;
  stderr: string;
}

/**
 * Run a fixed-shape PowerShell command. The command is built from an array
 * of fixed string parts; user input never participates in command
 * construction. `args` are passed as PowerShell positional parameters to the
 * embedded script.
 *
 * Use only with the curated commands in this module. Do not export a
 * generic "run any PowerShell" helper.
 */
async function runFixedPs(
  scriptBody: string,
  opts: { timeoutMs?: number } = {},
): Promise<PSResult> {
  const timeoutMs = opts.timeoutMs ?? 30 * 1000;

  return await new Promise<PSResult>((resolve) => {
    let stdout = '';
    let stderr = '';
    let killed = false;

    const child = spawn(
      'powershell.exe',
      ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', scriptBody],
      { shell: false, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] },
    );

    const timer = setTimeout(() => {
      killed = true;
      try { child.kill('SIGTERM'); } catch { /* best-effort */ }
    }, timeoutMs);

    child.stdout?.on('data', (b: Buffer) => { stdout += b.toString('utf8'); });
    child.stderr?.on('data', (b: Buffer) => { stderr += b.toString('utf8'); });

    child.on('error', (err) => {
      clearTimeout(timer);
      resolve({ exitCode: -1, stdout, stderr: stderr + `\n[spawn error] ${err.message}` });
    });
    child.on('exit', (code) => {
      clearTimeout(timer);
      resolve({ exitCode: killed ? -1 : (code ?? -1), stdout, stderr });
    });
  });
}

/**
 * Get the list of Nightingale-* scheduled tasks as parsed JSON. Returns null
 * if PowerShell call fails entirely (e.g. user disabled Task Scheduler service).
 */
export async function getNightingaleScheduledTasks(): Promise<NightingaleTaskInfo[] | null> {
  // Fixed PowerShell — no interpolation. Pipes Get-ScheduledTask + Get-ScheduledTaskInfo
  // results through ConvertTo-Json for stable parsing on this side.
  const script = `
    $tasks = Get-ScheduledTask -TaskName 'Nightingale-*' -ErrorAction SilentlyContinue
    if (-not $tasks) {
      Write-Output '[]'
      exit 0
    }
    $rows = foreach ($t in $tasks) {
      $info = $null
      try { $info = $t | Get-ScheduledTaskInfo -ErrorAction Stop } catch {}
      [PSCustomObject]@{
        name           = $t.TaskName
        state          = "$($t.State)"
        description    = "$($t.Description)"
        last_run_time  = if ($info) { $info.LastRunTime.ToString('o') } else { $null }
        next_run_time  = if ($info) { $info.NextRunTime.ToString('o') } else { $null }
        last_task_result = if ($info) { [int]$info.LastTaskResult } else { $null }
      }
    }
    $rows | ConvertTo-Json -Depth 3 -Compress
  `;
  const result = await runFixedPs(script);
  if (result.exitCode !== 0) return null;
  try {
    const parsed = JSON.parse(result.stdout || '[]');
    return Array.isArray(parsed) ? parsed : [parsed];
  } catch {
    return null;
  }
}

export interface NightingaleTaskInfo {
  name: string;
  state: string;
  description: string;
  last_run_time: string | null;
  next_run_time: string | null;
  last_task_result: number | null;
}

export interface WriteSecretsResult {
  ok: boolean;
  written_fields?: string[];
  schema_version?: number;
  error?: string;
  raw_stdout?: string;
  raw_stderr?: string;
}

/**
 * Write/merge secrets.json by invoking scripts/write-secrets.ps1 with the
 * secret values delivered on STDIN as a single JSON object — never on argv, so
 * the values never appear in any process listing. The script does the ACL-first
 * atomic write and prints a JSON result on its last stdout line.
 *
 * This is the ONLY place the server can mutate secrets.json, and only via the
 * dedicated, fixed script path (no interpolation, no arbitrary PowerShell).
 */
export async function writeSecrets(jsonPayload: string): Promise<WriteSecretsResult> {
  const scriptPath = path.join(repoRoot(), 'scripts', 'write-secrets.ps1');
  return await new Promise<WriteSecretsResult>((resolve) => {
    let stdout = '';
    let stderr = '';
    let settled = false;
    const child = spawn(
      'powershell.exe',
      ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', scriptPath],
      { shell: false, windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] },
    );
    const timer = setTimeout(() => {
      try { child.kill('SIGTERM'); } catch { /* best-effort */ }
    }, 60 * 1000);

    const finish = (r: WriteSecretsResult) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve(r);
    };

    child.stdout?.on('data', (b: Buffer) => { stdout += b.toString('utf8'); });
    child.stderr?.on('data', (b: Buffer) => { stderr += b.toString('utf8'); });
    child.on('error', (err) => finish({ ok: false, error: `spawn_error: ${err.message}` }));
    child.on('exit', (code) => {
      // The script prints a single-line JSON result. Parse the last non-empty
      // line so any informational Write-Host lines above it are tolerated.
      const lines = stdout.split(/\r?\n/).map((l) => l.trim()).filter(Boolean);
      for (let i = lines.length - 1; i >= 0; i--) {
        try {
          const parsed = JSON.parse(lines[i]) as WriteSecretsResult;
          if (typeof parsed.ok === 'boolean') {
            finish({ ...parsed, raw_stderr: stderr || undefined });
            return;
          }
        } catch {
          // not JSON — keep scanning upward
        }
      }
      finish({
        ok: code === 0,
        error: code === 0 ? 'no_result_json' : `exit_${code}`,
        raw_stdout: stdout.slice(-2000) || undefined,
        raw_stderr: stderr.slice(-2000) || undefined,
      });
    });

    // Deliver the payload on stdin and close it.
    try {
      child.stdin?.write(jsonPayload);
      child.stdin?.end();
    } catch {
      finish({ ok: false, error: 'stdin_write_failed' });
    }
  });
}

