#!/usr/bin/env bash
# Run both live detection queries against atdr-law BEFORE (or without) the analytics rules:
#  1. exactly as the rule runs them now (last 15 min),
#  2. replayed over the last 24 h in 15-minute windows (which windows would have raised an alert),
#  3. RateLimitDemo blocks per client per minute (how many blocks one burst produces).
# Client IPs are masked in the output: our own test laptop (User-Agent ATDR-waf-tests) -> <tester-ip>,
# everyone else -> first two octets only. Usage: bash detection-live/test-queries.sh [> evidence/05-...txt]
set -euo pipefail
source "$(dirname "$0")/../infra/common.sh"
HERE="$(dirname "$0")"
KQL="$REPO_ROOT/infra/kql.sh"

VM_ID="$(az vm show -g "$RG" -n "$VM_NAME" --query id -o tsv | tr -d '\r')"
MASK_LET='let _tester = toscalar(AGWAccessLogs | where UserAgent startswith "ATDR-waf-tests" | summarize take_any(ClientIp));'
MASK='| extend ClientIp = iff(ClientIp == _tester, "<tester-ip>", strcat(extract(@"^(\d+\.\d+)\.", 1, ClientIp), ".x.x"))'

live_query() { sed "s#__PROTECTED_VM_ID__#$VM_ID#" "$HERE/$1"; }
replay() {  # 15-minute tumbling windows over 24 h instead of "the last 15 minutes"
  live_query "$1" | sed -E \
    -e 's#\| where TimeGenerated > ago\(15m\)#| where TimeGenerated > ago(1d) | extend window15m = bin(TimeGenerated, 15m)#' \
    -e 's#^    by ClientIp#    by window15m, ClientIp#' \
    -e 's#^    TimeGenerated = lastSeen,#    window15m, TimeGenerated = lastSeen,#'
}
run() { bash "$KQL" --timespan P1D "$MASK_LET
$1
$MASK" | sanitize; }

echo "# Phase 5 — live detection queries run manually against atdr-law at $(utc_now)"
for q in waf-repeated-blocks.kql waf-rate-limit.kql; do
  echo; echo "## $q — as the analytics rule runs it (last 15 minutes)"
  run "$(live_query "$q")"
  echo; echo "## $q — replayed over the last 24 h in 15-minute windows (rows = windows that would alert)"
  run "$(replay "$q") | project-away sampleUris | order by window15m asc"
done

echo; echo "## RateLimitDemo blocks per client per minute (blocks produced by one burst)"
run 'AGWFirewallLogs
| where TimeGenerated > ago(1d) and RuleId == "RateLimitDemo" and Action =~ "Blocked"
| summarize rateLimitBlocks = dcount(TransactionId) by minute = bin(TimeGenerated, 1m), ClientIp, InstanceId
| order by minute asc'

echo; echo "## T5 bursts from our test laptop (T5 burst requests and their 403s per minute)"
run 'AGWAccessLogs
| where TimeGenerated > ago(1d) and UserAgent startswith "ATDR-waf-tests" and RequestQuery == "search=lock"
| summarize requests = count(), http403 = countif(HttpStatus == 403) by minute = bin(TimeGenerated, 1m), ClientIp, InstanceId
| order by minute asc'
