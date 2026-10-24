#!/usr/bin/env bash
# Run a KQL query against atdr-law through the Log Analytics query REST API
# (no CLI extension needed) and print the result as a table or JSON.
# Usage: bash infra/kql.sh [--json] [--timespan P1D] '<KQL>'      or      -f file.kql
set -euo pipefail
source "$(dirname "$0")/common.sh"

FORMAT=table
TIMESPAN=P1D
QUERY=""
while (( $# )); do
  case "$1" in
    --json) FORMAT=json ;;
    --timespan) TIMESPAN="$2"; shift ;;
    -f) QUERY="$(cat "$2")"; shift ;;
    *) QUERY="$1" ;;
  esac
  shift
done
[[ -n "$QUERY" ]] || { echo "usage: kql.sh [--json] [--timespan P1D] '<KQL>' | -f file.kql" >&2; exit 2; }

WS_GUID="$(az monitor log-analytics workspace show -g "$RG" -n "$LAW" --query customerId -o tsv | tr -d '\r')"
BODY="$(mktemp)"; trap 'rm -f "$BODY"' EXIT
QUERY="$QUERY" TIMESPAN="$TIMESPAN" python -c 'import json,os,sys; json.dump({"query":os.environ["QUERY"],"timespan":os.environ["TIMESPAN"]}, open(sys.argv[1],"w"))' "$(winpath "$BODY")"

az rest --method post --resource "https://api.loganalytics.io" \
  --url "https://api.loganalytics.io/v1/workspaces/$WS_GUID/query" \
  --body @"$(winpath "$BODY")" -o json \
| FORMAT="$FORMAT" python -c '
import json, os, sys
sys.stdout.reconfigure(encoding="utf-8")
raw = sys.stdin.buffer.read()   # az output is cp1252 on Windows when piped
try: d = json.loads(raw.decode("utf-8"))
except UnicodeDecodeError: d = json.loads(raw.decode("cp1252"))
t = d["tables"][0]
cols = [c["name"] for c in t["columns"]]
rows = [dict(zip(cols, r)) for r in t["rows"]]
if os.environ["FORMAT"] == "json":
    print(json.dumps(rows, indent=2, ensure_ascii=False)); sys.exit()
if not rows:
    print("(no rows)"); sys.exit()
w = {c: min(60, max(len(c), *(len(str(r[c])) for r in rows))) for c in cols}
print("  ".join(c.ljust(w[c]) for c in cols))
print("  ".join("-" * w[c] for c in cols))
for r in rows:
    print("  ".join(str(r[c])[:60].ljust(w[c]) for c in cols))
print("({} rows)".format(len(rows)))
'
