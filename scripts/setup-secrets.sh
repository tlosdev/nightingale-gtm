#!/usr/bin/env bash
#
# setup-secrets.sh
#
# Captures the user's LinkedIn li_at cookie and Apify API token, validates the
# Apify token, and writes both to ~/.nightingale/secrets.json with mode 0600.
#
# One-time per-user setup for the intro-finder agent. Re-run to rotate either
# secret; existing values are preserved unless you choose to overwrite.
#
# The Apify token is validated immediately against /v2/users/me. The LinkedIn
# cookie is held opaquely and validated on the first intro-finder Apify call
# (Sun-Thu mornings).
#
# Secrets file lives outside the repo: $HOME/.nightingale/secrets.json
# Cannot be accidentally git-add'd.

set -euo pipefail

secrets_dir="$HOME/.nightingale"
secrets_path="$secrets_dir/secrets.json"

# Preflight: python3 + curl required
if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: python3 is required (used to read/write JSON safely)." >&2
    exit 1
fi
if ! command -v curl >/dev/null 2>&1; then
    echo "ERROR: curl is required (used to validate the Apify token)." >&2
    exit 1
fi

mkdir -p "$secrets_dir"
chmod 700 "$secrets_dir"

# Load existing values (if any)
existing_li_at=""
existing_apify=""
existing_created_at=""
if [ -f "$secrets_path" ]; then
    echo "Existing secrets file found at $secrets_path."
    existing_li_at="$(python3 -c "
import json
try:
    print((json.load(open('$secrets_path')).get('linkedin_li_at') or ''))
except Exception:
    print('')
")"
    existing_apify="$(python3 -c "
import json
try:
    print((json.load(open('$secrets_path')).get('apify_api_token') or ''))
except Exception:
    print('')
")"
    existing_created_at="$(python3 -c "
import json
try:
    print((json.load(open('$secrets_path')).get('created_at') or ''))
except Exception:
    print('')
")"
else
    echo "Creating new secrets file at $secrets_path."
fi

# Decide whether to (re)prompt
prompt_li_at=1
prompt_apify=1
if [ -n "$existing_li_at" ]; then
    read -r -p "Overwrite existing linkedin_li_at? [y/N] " resp
    case "$resp" in
        [Yy]*) prompt_li_at=1 ;;
        *)     prompt_li_at=0 ;;
    esac
fi
if [ -n "$existing_apify" ]; then
    read -r -p "Overwrite existing apify_api_token? [y/N] " resp
    case "$resp" in
        [Yy]*) prompt_apify=1 ;;
        *)     prompt_apify=0 ;;
    esac
fi

# Prompt for li_at
new_li_at="$existing_li_at"
if [ "$prompt_li_at" -eq 1 ]; then
    echo ""
    echo "LinkedIn li_at cookie setup"
    echo "---"
    echo "1. Open Chrome -> linkedin.com (log in if needed)"
    echo "2. Press F12 -> DevTools -> 'Application' tab"
    echo "3. Left sidebar: Storage -> Cookies -> https://www.linkedin.com"
    echo "4. Find the row named 'li_at' and copy the Value column"
    echo ""
    read -r -s -p "Paste li_at value (input hidden): " new_li_at
    echo ""
    new_li_at="$(printf '%s' "$new_li_at" | python3 -c "import sys; print(sys.stdin.read().strip())")"
    if [ -z "$new_li_at" ]; then
        echo "ERROR: empty li_at value. Aborting." >&2
        exit 1
    fi
fi

# Prompt for Apify token
new_apify="$existing_apify"
if [ "$prompt_apify" -eq 1 ]; then
    echo ""
    echo "Apify API token setup"
    echo "---"
    echo "Get your token from: https://console.apify.com/account/integrations"
    echo ""
    read -r -s -p "Paste Apify API token (input hidden): " new_apify
    echo ""
    new_apify="$(printf '%s' "$new_apify" | python3 -c "import sys; print(sys.stdin.read().strip())")"
    if [ -z "$new_apify" ]; then
        echo "ERROR: empty Apify token. Aborting." >&2
        exit 1
    fi
fi

# Validate Apify token
echo ""
echo "Validating Apify token..."
validate_tmp="$(mktemp)"
http_code="$(curl -sS -o "$validate_tmp" -w '%{http_code}' \
    -H "Authorization: Bearer $new_apify" \
    "https://api.apify.com/v2/users/me" || true)"
if [ "$http_code" != "200" ]; then
    echo "ERROR: Apify token validation failed (HTTP $http_code). Secrets file NOT written." >&2
    rm -f "$validate_tmp"
    exit 1
fi
apify_user="$(python3 -c "
import json
try:
    print(json.load(open('$validate_tmp')).get('data', {}).get('username') or '(no username)')
except Exception:
    print('(no username)')
")"
rm -f "$validate_tmp"
echo "Apify token OK (user: $apify_user)"
echo "LinkedIn li_at not validated here (validated on first intro-finder Apify call)."

# Preserve created_at; bump updated_at to today
today="$(date +%Y-%m-%d)"
created_at="${existing_created_at:-$today}"

# Emit JSON via python (argv avoids shell escaping pitfalls)
python3 - "$secrets_path" "$created_at" "$today" "$new_li_at" "$new_apify" <<'PYEOF'
import json, os, sys
path, created_at, updated_at, li_at, apify = sys.argv[1:6]
data = {
    "schema_version": 1,
    "created_at": created_at,
    "updated_at": updated_at,
    "linkedin_li_at": li_at,
    "apify_api_token": apify,
}
with open(path, "w") as f:
    json.dump(data, f, indent=2)
os.chmod(path, 0o600)
PYEOF

# Clear sentinel if the user just refreshed credentials
sentinel="$secrets_dir/.cookie-expired-active"
if [ -f "$sentinel" ]; then
    rm -f "$sentinel"
    echo "Cleared cookie-expired sentinel."
fi

echo ""
echo "Done. Secrets written to: $secrets_path"
echo "Next intro-finder run (Sun-Thu 7am) will use these credentials."
