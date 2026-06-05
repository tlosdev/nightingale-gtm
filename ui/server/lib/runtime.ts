// Run-mode detection. The UI can run two ways:
//
//  - HOST (native, via scripts/start-ui.ps1): the Express process is the
//    operator's own session. It can spawn `claude -p` and PowerShell directly,
//    so every action (agent runs, approvals, secrets editing, scheduled-task
//    reads) works.
//
//  - CONTAINER (Docker, via docker-compose): the process runs in a Linux
//    container. It can READ the mounted Desktop output tree + secrets file and
//    render the whole dashboard, but it CANNOT spawn the host `claude` CLI
//    (no claude.ai MCP auth inside the container) nor PowerShell. Those actions
//    are disabled with a clear message until the Phase 3 self-hosted GitHub
//    runner gives us a `workflow_dispatch` path that works from inside a
//    container too.
//
// Docker reproduces the UI + the agent *definitions* (static text), not the
// agent *runtime*. That honesty note also lives in ui/README.md.
import fs from 'node:fs';

export type RunMode = 'host' | 'container';

let cachedContainer: boolean | null = null;

export function isContainer(): boolean {
  if (cachedContainer !== null) return cachedContainer;
  // Explicit env (set by the Dockerfile / docker-compose) is authoritative.
  const flag = process.env.NIGHTINGALE_CONTAINER;
  if (flag === '1' || flag === 'true') {
    cachedContainer = true;
    return cachedContainer;
  }
  // Fallback heuristic: Docker creates /.dockerenv at the container root.
  try {
    cachedContainer = fs.existsSync('/.dockerenv');
  } catch {
    cachedContainer = false;
  }
  return cachedContainer;
}

export function runMode(): RunMode {
  return isContainer() ? 'container' : 'host';
}

/**
 * Whether host-side subprocesses (claude CLI, PowerShell) can be spawned.
 * Host: yes. Container: no (until Phase 3 wires GitHub workflow_dispatch).
 */
export function canSpawnHostProcess(): boolean {
  return !isContainer();
}

export const CONTAINER_ACTION_MESSAGE =
  'This action is unavailable in Docker (container) mode: the container cannot ' +
  'reach the host Claude Code CLI / claude.ai MCP connectors or PowerShell. ' +
  'Run the UI natively on the host (scripts/start-ui.ps1) to trigger agents, ' +
  'approvals, or secrets edits — or wait for the Phase 3 GitHub self-hosted ' +
  'runner dispatch path.';
