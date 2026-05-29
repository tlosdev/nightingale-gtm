#!/usr/bin/env bash
#
# run-one-apify-call.sh
#
# Performs a single Apify-driven LinkedIn mutual-connections lookup for one
# target, and writes the result JSON to disk. Invoked by an OS one-shot task
# scheduled by the intro-finder morning agent.
#
# Args:
#   --side               commercial | academic
#   --target-url         LinkedIn profile URL of the target
#   --target-meta-path   path to a small JSON file with target metadata
#   --result-path        where to write the result JSON
#   [--actor-id]         Apify Actor ID. Default from NIGHTINGALE_APIFY_ACTOR env
#                        or 'apimaestro~linkedin-profile-batch-scraper' placeholder.
#
# Never logs the li_at value. Detects cookie-expired indicators and writes
# sentinel files so the morning agent can short-circuit subsequent calls.

set -euo pipefail

side=""
target_url=""
target_meta_path=""
result_path=""
actor_id="${NIGHTINGALE_APIFY_ACTOR:-apimaestro~linkedin-profile-batch-scraper}"

while [ $# -gt 0 ]; do
    case "$1" in
        --side)             side="$2"; shift 2 ;;
        --target-url)       target_url="$2"; shift 2 ;;
        --target-meta-path) target_meta_path="$2"; shift 2 ;;
        --result-path)      result_path="$2"; shift 2 ;;
        --actor-id)         actor_id="$2"; shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done

if [ -z "$side" ] || [ -z "$target_url" ] || [ -z "$target_meta_path" ] || [ -z "$result_path" ]; then
    echo "Usage: run-one-apify-call.sh --side <s> --target-url <u> --target-meta-path <p> --result-path <p> [--actor-id <id>]" >&2
    exit 2
fi

secrets_dir="$HOME/.nightingale"
secrets_path="$secrets_dir/secrets.json"
sentinel_active="$secrets_dir/.cookie-expired-active"
today="$(date +%Y-%m-%d)"
sentinel_today="$HOME/Desktop/nightingale-signals/.cookie-expired-$today"

result_dir="$(dirname "$result_path")"
mkdir -p "$result_dir"

# Write a structured result JSON via python (safe escaping)
write_result() {
    local status="$1"
    local error_msg="$2"
    local apify_run_id="$3"
    local mutuals_json="${4:-[]}"

    python3 - "$result_path" "$side" "$target_url" "$target_meta_path" \
        "$actor_id" "$status" "$error_msg" "$apify_run_id" "$mutuals_json" <<'PYEOF'
import json, os, sys, datetime
(path, side, target_url, target_meta_path, actor_id,
 status, error_msg, apify_run_id, mutuals_json) = sys.argv[1:10]

meta = None
try:
    with open(target_meta_path) as f:
        meta = json.load(f)
except Exception:
    meta = None

try:
    mutuals = json.loads(mutuals_json)
except Exception:
    mutuals = []

payload = {
    "side": side,
    "target_url": target_url,
    "target_meta": meta,
    "actor_id": actor_id,
    "invoked_at": datetime.datetime.now().isoformat(timespec="seconds"),
    "status": status,
    "apify_run_id": apify_run_id or None,
    "mutuals": mutuals,
    "error": (error_msg or None),
}
with open(path, "w") as f:
    json.dump(payload, f, indent=2)
PYEOF
}

# Secrets missing?
if [ ! -f "$secrets_path" ]; then
    write_result "secrets_missing" "Secrets file not found at $secrets_path. Run scripts/setup-secrets." "" "[]"
    exit 0
fi

# Sentinel active?
if [ -f "$sentinel_active" ]; then
    write_result "skipped_cookie_expired" "Cookie-expired sentinel active. Re-run scripts/setup-secrets." "" "[]"
    exit 0
fi

# Read secrets
apify_token="$(python3 -c "
import json
try:
    print((json.load(open('$secrets_path')).get('apify_api_token') or ''))
except Exception:
    print('')
")"
li_at="$(python3 -c "
import json
try:
    print((json.load(open('$secrets_path')).get('linkedin_li_at') or ''))
except Exception:
    print('')
")"

if [ -z "$apify_token" ] || [ -z "$li_at" ]; then
    write_result "secrets_incomplete" "Missing apify_api_token or linkedin_li_at." "" "[]"
    exit 0
fi

# Build input payload (python to safely escape the cookie + URL)
input_payload_path="$(mktemp)"
python3 - "$input_payload_path" "$target_url" "$li_at" <<'PYEOF'
import json, sys
path, target_url, li_at = sys.argv[1:4]
data = {
    "targetUrl": target_url,
    "sessionCookie": li_at,
    "proxyConfiguration": {
        "useApifyProxy": True,
        "apifyProxyGroups": ["RESIDENTIAL"],
    },
}
with open(path, "w") as f:
    json.dump(data, f)
PYEOF

# Start the Apify run
start_tmp="$(mktemp)"
http_code="$(curl -sS -o "$start_tmp" -w '%{http_code}' \
    -X POST \
    -H "Content-Type: application/json" \
    --data @"$input_payload_path" \
    "https://api.apify.com/v2/acts/$actor_id/runs?token=$apify_token" || true)"
rm -f "$input_payload_path"

if [ "$http_code" != "201" ] && [ "$http_code" != "200" ]; then
    write_result "apify_start_failed" "Apify run start returned HTTP $http_code" "" "[]"
    rm -f "$start_tmp"
    exit 0
fi

run_id="$(python3 -c "
import json
try:
    print(json.load(open('$start_tmp')).get('data', {}).get('id') or '')
except Exception:
    print('')
")"
rm -f "$start_tmp"

if [ -z "$run_id" ]; then
    write_result "apify_start_failed" "Apify did not return a run id" "" "[]"
    exit 0
fi

# Poll for completion (5s -> 30s cap, ~3min total)
delay=5
total_slept=0
max_total=180
final_status=""
while [ "$total_slept" -lt "$max_total" ]; do
    sleep "$delay"
    total_slept=$((total_slept + delay))
    status_tmp="$(mktemp)"
    code="$(curl -sS -o "$status_tmp" -w '%{http_code}' \
        "https://api.apify.com/v2/acts/$actor_id/runs/$run_id?token=$apify_token" || true)"
    if [ "$code" = "200" ]; then
        final_status="$(python3 -c "
import json
try:
    print(json.load(open('$status_tmp')).get('data', {}).get('status') or '')
except Exception:
    print('')
")"
    fi
    rm -f "$status_tmp"
    case "$final_status" in
        SUCCEEDED|FAILED|ABORTED|TIMED-OUT|TIMEOUT) break ;;
    esac
    if [ "$delay" -lt 30 ]; then
        delay=$((delay * 2))
        if [ "$delay" -gt 30 ]; then delay=30; fi
    fi
done

if [ "$final_status" != "SUCCEEDED" ]; then
    write_result "apify_run_not_succeeded" "Apify run finished with status: ${final_status:-unknown} after ${total_slept}s" "$run_id" "[]"
    exit 0
fi

# Fetch dataset items
items_tmp="$(mktemp)"
code="$(curl -sS -o "$items_tmp" -w '%{http_code}' \
    "https://api.apify.com/v2/acts/$actor_id/runs/$run_id/dataset/items?token=$apify_token" || true)"
if [ "$code" != "200" ]; then
    write_result "apify_fetch_failed" "Dataset fetch HTTP $code" "$run_id" "[]"
    rm -f "$items_tmp"
    exit 0
fi

# Detect cookie expiry + normalize + dedupe in python (one pass)
detect_and_normalize="$(python3 - "$items_tmp" <<'PYEOF'
import json, re, sys
path = sys.argv[1]
try:
    raw = open(path).read()
    items = json.loads(raw) if raw.strip() else []
    if not isinstance(items, list):
        items = []
except Exception:
    items = []

flag_re = re.compile(r"loginRequired|captcha|restricted|authwall|please[ _-]?log[ _-]?in", re.I)
flagged = False
joined = json.dumps(items)
if flag_re.search(joined):
    flagged = True

mutuals = []
seen = set()
if not flagged:
    for it in items:
        if not isinstance(it, dict):
            continue
        name = it.get("name") or it.get("fullName") or it.get("full_name")
        url = it.get("url") or it.get("profileUrl") or it.get("linkedinUrl")
        title = it.get("title") or it.get("headline") or it.get("currentTitle")
        company = it.get("company") or it.get("currentCompany") or it.get("companyName")
        if not url and not name:
            continue
        key = url or name
        if key in seen:
            continue
        seen.add(key)
        mutuals.append({
            "name": name,
            "url": url,
            "current_title": title,
            "current_company": company,
        })

print(json.dumps({"flagged": flagged, "mutuals": mutuals}))
PYEOF
)"
rm -f "$items_tmp"

flagged="$(echo "$detect_and_normalize" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())['flagged'])")"
mutuals_json="$(echo "$detect_and_normalize" | python3 -c "import json,sys; print(json.dumps(json.loads(sys.stdin.read())['mutuals']))")"

if [ "$flagged" = "True" ]; then
    # Set sentinels (best-effort)
    : > "$sentinel_active" || true
    mkdir -p "$(dirname "$sentinel_today")" || true
    : > "$sentinel_today" || true
    write_result "cookie_expired" "Apify Actor returned auth-failure indicators. Sentinels set." "$run_id" "[]"
    exit 0
fi

write_result "succeeded" "" "$run_id" "$mutuals_json"
exit 0
