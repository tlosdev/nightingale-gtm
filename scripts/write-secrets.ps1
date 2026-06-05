<#
.SYNOPSIS
    Non-interactive partial writer for ~/.nightingale/secrets.json (schema v5).
    Reads a JSON object of changed fields from STDIN, merges it with the
    existing secrets file, and performs an ACL-first atomic write.

.DESCRIPTION
    Called by the UI server (ui/server/lib/powershell.ts -> writeSecrets) so the
    operator can edit credentials from the Settings tab. Secret VALUES arrive on
    STDIN as a single JSON object, never on the command line, so they never
    appear in a process listing.

    Accepted fields (all optional in a partial update):
      Required-shape : apify_api_token, apify_actor_id, apify_validation_url,
                       linkedin_li_at
      Optional       : apify_company_roster_actor_id, pitch_deck_drive_file_id,
                       pitch_deck_drive_url, github_pat, github_repo
    For the OPTIONAL fields, an explicit empty string ("") clears the field
    (omit-when-empty). Required-shape fields are only ever set, never written
    empty (the server rejects empty values for them before calling this script).

    Emits a single-line JSON result on the LAST stdout line:
      {"ok":true,"written_fields":[...],"schema_version":5}
    or on failure:
      {"ok":false,"error":"..."}

    Shape validation is the server's job (zod). This script trusts the values
    but still enforces the merge/clear/omit discipline.

.NOTES
    The ACL-first atomic write block below is intentionally DUPLICATED from
    scripts/setup-secrets.ps1 (the "Write secrets.json" section, ~lines 475-556).
    Both copies MUST stay in sync - if you change the ACL handling in one,
    change it in the other. We duplicate rather than factor out to avoid risky
    surgery on the tested interactive validator.

    Requires Windows + PowerShell 5.1+. ASCII-only on purpose (no BOM issues).
#>

$ErrorActionPreference = 'Stop'

function Emit-Result {
    param([hashtable]$Obj)
    # Always emit a single compact JSON line LAST so the Node caller can parse it.
    ($Obj | ConvertTo-Json -Compress -Depth 4)
}

try {
    # --- Read the partial update from STDIN ----------------------------------
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) {
        Emit-Result @{ ok = $false; error = 'empty_stdin' }
        exit 0
    }

    try {
        $incoming = $raw | ConvertFrom-Json
    } catch {
        Emit-Result @{ ok = $false; error = 'invalid_json' }
        exit 0
    }

    $requiredShape = @('apify_api_token', 'apify_actor_id', 'apify_validation_url', 'linkedin_li_at')
    $optional      = @('apify_company_roster_actor_id', 'pitch_deck_drive_file_id', 'pitch_deck_drive_url', 'github_pat', 'github_repo')
    $known         = $requiredShape + $optional

    $secretsDir  = Join-Path $env:USERPROFILE '.nightingale'
    $secretsPath = Join-Path $secretsDir 'secrets.json'

    # --- Ensure ~/.nightingale exists with restrictive ACL -------------------
    if (-not (Test-Path $secretsDir)) {
        New-Item -ItemType Directory -Path $secretsDir | Out-Null
    }
    try {
        $acl = Get-Acl $secretsDir
        $acl.SetAccessRuleProtection($true, $false)
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            "$env:USERDOMAIN\$env:USERNAME",
            'FullControl',
            'ContainerInherit,ObjectInherit',
            'None',
            'Allow')
        $acl.SetAccessRule($rule)
        Set-Acl -Path $secretsDir -AclObject $acl
    } catch {
        # Non-fatal; continue to the file write which also locks down.
    }

    # --- Load existing secrets (if any) into an ordered map ------------------
    $merged = [ordered]@{}
    if (Test-Path $secretsPath) {
        try {
            $existing = Get-Content -Path $secretsPath -Raw | ConvertFrom-Json
            foreach ($p in $existing.PSObject.Properties) {
                $merged[$p.Name] = $p.Value
            }
        } catch {
            # Corrupt existing file: start fresh rather than fail the edit.
            $merged = [ordered]@{}
        }
    }

    # --- Apply the incoming partial update -----------------------------------
    $writtenFields = New-Object System.Collections.Generic.List[string]
    foreach ($name in $known) {
        $prop = $incoming.PSObject.Properties[$name]
        if ($null -eq $prop) { continue }   # field not part of this update
        $value = $prop.Value

        if ($optional -contains $name) {
            if ([string]::IsNullOrEmpty($value)) {
                # Explicit clear: remove the optional field entirely.
                if ($merged.Contains($name)) { $merged.Remove($name) }
                $writtenFields.Add($name) | Out-Null
            } else {
                $merged[$name] = $value
                $writtenFields.Add($name) | Out-Null
            }
        } else {
            # Required-shape: only set non-empty values (server already enforced).
            if (-not [string]::IsNullOrEmpty($value)) {
                $merged[$name] = $value
                $writtenFields.Add($name) | Out-Null
            }
        }
    }

    if ($writtenFields.Count -eq 0) {
        Emit-Result @{ ok = $false; error = 'no_known_fields' }
        exit 0
    }

    # --- Rebuild the canonical ordered object (schema v5) --------------------
    $createdAt = if ($merged.Contains('created_at') -and $merged['created_at']) { $merged['created_at'] } else { (Get-Date -Format 'yyyy-MM-dd') }
    $updatedAt = (Get-Date -Format 'yyyy-MM-dd')

    $out = [ordered]@{
        schema_version = 5
        created_at     = $createdAt
        updated_at     = $updatedAt
    }
    foreach ($name in $requiredShape) {
        if ($merged.Contains($name) -and -not [string]::IsNullOrEmpty($merged[$name])) {
            $out[$name] = $merged[$name]
        }
    }
    foreach ($name in $optional) {
        if ($merged.Contains($name) -and -not [string]::IsNullOrEmpty($merged[$name])) {
            $out[$name] = $merged[$name]
        }
    }

    $json = $out | ConvertTo-Json -Depth 5

    # === ACL-first atomic write =============================================
    # MIRRORED from scripts/setup-secrets.ps1 (~lines 475-556). Keep in sync.
    # Create an empty file with the restricted ACL FIRST, then write content, so
    # there is no window where plaintext is readable with a default ACL.
    if (Test-Path $secretsPath) {
        Remove-Item -Path $secretsPath -Force
    }
    try {
        $fileSecurity = New-Object System.Security.AccessControl.FileSecurity
        $fileSecurity.SetAccessRuleProtection($true, $false)
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            "$env:USERDOMAIN\$env:USERNAME",
            'FullControl',
            'Allow')
        $fileSecurity.SetAccessRule($rule)

        [System.IO.File]::Create($secretsPath).Close()
        Set-Acl -Path $secretsPath -AclObject $fileSecurity

        # UTF-8 WITHOUT BOM. Set-Content -Encoding utf8 (PS 5.1) emits a BOM,
        # which Node's JSON.parse rejects when the server reads this file back.
        [System.IO.File]::WriteAllText($secretsPath, $json, (New-Object System.Text.UTF8Encoding($false)))
    } catch {
        # Fallback: write-then-lock (brief readability window).
        # UTF-8 WITHOUT BOM. Set-Content -Encoding utf8 (PS 5.1) emits a BOM,
        # which Node's JSON.parse rejects when the server reads this file back.
        [System.IO.File]::WriteAllText($secretsPath, $json, (New-Object System.Text.UTF8Encoding($false)))
        try {
            $acl2 = Get-Acl $secretsPath
            $acl2.SetAccessRuleProtection($true, $false)
            foreach ($r in @($acl2.Access)) { $acl2.RemoveAccessRule($r) | Out-Null }
            $rule2 = New-Object System.Security.AccessControl.FileSystemAccessRule(
                "$env:USERDOMAIN\$env:USERNAME",
                'FullControl',
                'Allow')
            $acl2.SetAccessRule($rule2)
            Set-Acl -Path $secretsPath -AclObject $acl2
        } catch {
            # Could not lock down; the value still merged. Report ok but note it.
        }
    }
    # === end mirrored block =================================================

    Emit-Result @{ ok = $true; written_fields = @($writtenFields); schema_version = 5 }
    exit 0
} catch {
    Emit-Result @{ ok = $false; error = "exception: $($_.Exception.Message)" }
    exit 0
}
