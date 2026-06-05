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

export interface RunnerStatus {
  runner_present: boolean;
  runner_name: string | null;
  runner_status: string | null;   // 'Running' | 'Stopped' | ...
  runner_starttype: string | null; // 'Automatic' | 'Manual' | 'Disabled' | ...
  boot_catchup: boolean;           // Nightingale-Boot-Catchup task registered?
  legacy_agent_tasks: string[];    // any of the 8 legacy agent tasks still registered
}

// The eight legacy agent Task Scheduler entries (Phase 3 migrates off these).
// Nightingale-Boot-Catchup and the dynamic intro-finder one-shots are NOT in
// this list — their presence is normal post-migration.
const LEGACY_AGENT_TASKS = [
  'Nightingale-Daily-Brief-Morning',
  'Nightingale-Commercial-Sweep',
  'Nightingale-Academic-Sweep',
  'Nightingale-Intro-Finder-Morning',
  'Nightingale-Gmail-Resurfacer-Morning',
  'Nightingale-HubSpot-Manager-Nightly',
  'Nightingale-Investor-Analyzer-Weekly',
  'Nightingale-Investor-Newsletter-Biweekly',
];

/**
 * Detect the Phase 3 scheduling state on this host: is the GitHub Actions
 * self-hosted runner installed + running, is the on-boot catch-up task present,
 * and are any legacy Task Scheduler agents still around (which would double-fire)?
 * Returns null if PowerShell can't be invoked at all (non-Windows / container).
 */
export async function getRunnerStatus(): Promise<RunnerStatus | null> {
  // Fixed PowerShell — no interpolation.
  const legacyList = LEGACY_AGENT_TASKS.map((n) => `'${n}'`).join(',');
  const script = `
    $svc = Get-Service -Name 'actions.runner.*' -ErrorAction SilentlyContinue | Select-Object -First 1
    $startType = $null
    if ($svc) { try { $startType = "$($svc.StartType)" } catch { $startType = $null } }
    $legacyNames = @(${legacyList})
    # One enumeration of all Nightingale-* tasks, then partition in-memory --
    # cheaper than N per-name CIM lookups (which are slow on a cold call).
    $allTasks = @(Get-ScheduledTask -TaskName 'Nightingale-*' -ErrorAction SilentlyContinue | ForEach-Object { $_.TaskName })
    $legacy = @($allTasks | Where-Object { $legacyNames -contains $_ })
    $boot = [bool]($allTasks -contains 'Nightingale-Boot-Catchup')
    [PSCustomObject]@{
      runner_present     = [bool]$svc
      runner_name        = if ($svc) { $svc.Name } else { $null }
      runner_status      = if ($svc) { "$($svc.Status)" } else { $null }
      runner_starttype   = $startType
      boot_catchup       = $boot
      legacy_agent_tasks = @($legacy)
    } | ConvertTo-Json -Depth 3 -Compress
  `;
  const result = await runFixedPs(script);
  if (result.exitCode !== 0) return null;
  try {
    const parsed = JSON.parse(result.stdout) as Partial<RunnerStatus>;
    // ConvertTo-Json may emit a scalar/absent for a 0- or 1-length array; normalize.
    const legacyRaw = (parsed as { legacy_agent_tasks?: unknown }).legacy_agent_tasks;
    const legacy = Array.isArray(legacyRaw) ? legacyRaw : legacyRaw ? [legacyRaw] : [];
    return {
      runner_present: Boolean(parsed.runner_present),
      runner_name: parsed.runner_name ?? null,
      runner_status: parsed.runner_status ?? null,
      runner_starttype: parsed.runner_starttype ?? null,
      boot_catchup: Boolean(parsed.boot_catchup),
      legacy_agent_tasks: legacy.map((s) => String(s)),
    };
  } catch {
    return null;
  }
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

