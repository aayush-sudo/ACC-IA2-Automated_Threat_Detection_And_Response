#!/usr/bin/env bash
# Phase 6 — one end-to-end run: attack traffic -> WAF blocks -> Sentinel analytics rules -> incident ->
# automation rule -> atdr-playbook-contain -> VM isolated -> gateway 502 / backend Unhealthy.
# This script never starts the playbook itself; it only switches the automation rule on and watches.
#
#   bash tests/e2e_run.sh <run-number>             attack + watch until isolation is verified (~10-20 min)
#   bash tests/e2e_run.sh <run-number> --watch     re-attach the watcher to a run (same T0, no traffic)
#   bash tests/e2e_run.sh <name> --preflight        dry pre-flight only: no traffic, automation rule untouched
#   bash tests/e2e_run.sh <name> --manual           manual-response baseline: attack with the automation rule
#                                                  OFF, then record when each manual portal step shows up
#   bash tests/e2e_run.sh <run-number> --report    re-collect the report later
#   bash tests/e2e_run.sh <run-number> --close     after rollback: close the run's incidents (an open
#                                                  incident would absorb the next run's alerts)
#
# Traffic: 5 standard SQLi/XSS test strings (High rule: >= 5 blocked transactions) and a 50-request burst
# (Medium rule: >= 3 RateLimitDemo blocks), all from this laptop to our own gateway only.
# Leaves the VM ISOLATED for screenshots: restore with  bash response/rollback.sh --delete-snapshot
# Live log: evidence/raw/ (git-ignored). Final, masked report: evidence/06-e2e-run<N>.txt
set -Eeuo pipefail
source "$(dirname "$0")/../infra/common.sh"
source "$REPO_ROOT/detection-live/rule-ids.sh"

N="${1:?usage: e2e_run.sh <run-number> [--watch|--report|--close|--preflight|--manual]}"
MODE="${2:-run}"
RAW_DIR="$EVIDENCE_DIR/raw"; mkdir -p "$RAW_DIR"
RAW="$RAW_DIR/06-e2e-run$N.log"
STATE="$RAW_DIR/06-e2e-run$N.env"
OUT="$EVIDENCE_DIR/06-e2e-run$N.txt"
UA="ATDR-e2e/1.0 (college project; own gateway only)"
APPGW="atdr-appgw"
NIC="atdr-vm-backendVMNic"
PB_ID="/subscriptions/$SUB_ID/resourceGroups/$RG/providers/Microsoft.Logic/workflows/atdr-playbook-contain"
PIP="$(az network public-ip show -g "$RG" -n atdr-pip-appgw --query ipAddress -o tsv | tr -d '\r')"
URL="http://$PIP"

log() { echo "[$(utc_now)] $*" | tee -a "$RAW"; }
trap 'echo "[$(utc_now)] ERROR: exit $? at line $LINENO: $BASH_COMMAND" | tee -a "$RAW" >&2' ERR
# Parse az JSON from stdin (cp1252 on Windows when redirected) and run the Python snippet $1 on it as `d`.
pyj() { python -c "import json, sys
sys.stdout.reconfigure(encoding='utf-8')
raw = sys.stdin.buffer.read()
try: d = json.loads(raw.decode('utf-8'))
except UnicodeDecodeError: d = json.loads(raw.decode('cp1252'))
$1" "${@:2}"; }

incidents_since() {  # number|createdTimeUtc|severity|rule|guid|title
  az rest --method get -o json \
    --url "https://management.azure.com$SI/incidents?api-version=2024-03-01&\$orderby=properties/createdTimeUtc desc&\$top=10" |
  pyj '
t0, rb, rr, t1 = sys.argv[1], sys.argv[2].lower(), sys.argv[3].lower(), sys.argv[4]
for i in d["value"]:
    p = i["properties"]
    if p["createdTimeUtc"] < t0 or (t1 and p["createdTimeUtc"] > t1): continue
    rules = " ".join(p.get("relatedAnalyticRuleIds", [])).lower()
    rule = "repeated-blocks" if rb in rules else "rate-limit" if rr in rules else "other"
    print("|".join([str(p["incidentNumber"]), p["createdTimeUtc"], p["severity"], rule, i["name"], p["title"]]))
' "$1" "$RULE_BLOCKS_ID" "$RULE_RATE_ID" "${2:-}"
}
runs_since() {  # runName|startTime|endTime|status
  az rest --method get -o json --url "https://management.azure.com$PB_ID/runs?api-version=2016-06-01&\$top=10" |
  pyj '
for r in d["value"]:
    p = r["properties"]
    if p["startTime"] < sys.argv[1] or (sys.argv[2] and p["startTime"] > sys.argv[2]): continue
    print("|".join([r["name"], p["startTime"], p.get("endTime") or "-", p["status"]]))
' "$1" "${2:-}"
}
open_atdr_incidents() {  # number|guid of every not-Closed incident from our two rules
  az rest --method get -o json \
    --url "https://management.azure.com$SI/incidents?api-version=2024-03-01&\$orderby=properties/createdTimeUtc desc&\$top=50" |
  pyj '
rb, rr = sys.argv[1].lower(), sys.argv[2].lower()
for i in d["value"]:
    p = i["properties"]
    rules = " ".join(p.get("relatedAnalyticRuleIds", [])).lower()
    if p["status"] != "Closed" and (rb in rules or rr in rules):
        print("{}|{}".format(p["incidentNumber"], i["name"]))
' "$RULE_BLOCKS_ID" "$RULE_RATE_ID"
}
close_incident() {  # $1 guid: Closed / BenignPositive (our own test traffic) unless CLOSE_CLASS/_REASON/_COMMENT set
  local url="https://management.azure.com$SI/incidents/$1?api-version=2024-03-01" body
  body="$(mktemp)"
  az rest --method get -o json --url "$url" | pyj '
p = d["properties"]
keep = {k: p[k] for k in ("title", "severity", "description", "owner", "labels") if k in p}
import os; e = os.environ
keep.update(status="Closed", classification=e.get("CLOSE_CLASS") or "BenignPositive",
            classificationReason=e.get("CLOSE_REASON") or "SuspiciousButExpected",
            classificationComment=e.get("CLOSE_COMMENT") or "ATDR E2E test traffic from our own laptop; VM rolled back with response/rollback.sh.")
json.dump({"etag": d.get("etag"), "properties": keep}, open(sys.argv[1], "w"))
' "$(winpath "$body")"
  az rest --method put --url "$url" --body @"$(winpath "$body")" \
    --query "join(' ', ['incident', to_string(properties.incidentNumber), properties.status, properties.classification])" -o tsv
  rm -f "$body"
}
vm_state() {  # SecurityStatus|IncidentNumber|NIC NSG name
  local tags nsg
  tags="$(az vm show -g "$RG" -n "$VM_NAME" --query "join('|', [tags.SecurityStatus || '', tags.IncidentNumber || ''])" -o tsv | tr -d '\r')"
  nsg="$(az network nic show -g "$RG" -n "$NIC" --query "networkSecurityGroup.id" -o tsv | tr -d '\r')"
  echo "$tags|${nsg##*/}"
}
site_status() { curl -s -o /dev/null -m 40 -A "$UA" -w '%{http_code}' "$URL/" || true; }
backend_health() {
  az network application-gateway show-backend-health -g "$RG" -n "$APPGW" \
    --query "backendAddressPools[0].backendHttpSettingsCollection[0].servers[0].health" -o tsv | tr -d '\r'
}

report() {
  # shellcheck disable=SC1090
  source "$STATE"
  local T1   # report window: incidents/runs/health rows of THIS run only (every run finished within 45 min)
  T1="$(date -u -d "$T0 + 45 minutes" +%Y-%m-%dT%H:%M:%SZ)"
  {
    echo "# Phase 6 — E2E run $N (report collected $(utc_now)); IPs masked, IDs sanitised"
    echo "# Live log of the run: see 'Run log' at the end"
    echo
    echo "## Timeline"
    echo "T0 attack start          $T0"
    echo "attack end               $T_ATTACK_END"
    incidents_since "$T0" "$T1" | while IFS='|' read -r num created sev rule guid title; do
      echo "incident #$num created   $created  ($sev, rule $rule)"
    done
    runs_since "$T0" "$T1" | sort -t'|' -k2 | while IFS='|' read -r name start end status; do
      echo "playbook run start       $start  (run $name)"
      echo "playbook run end         $end  ($status)"
    done
    echo "isolation verified       ${T_ISOLATED:-not seen}  (poll: VM tag SecurityStatus=Quarantined and NIC on atdr-nsg-isolation)"
    echo "first 502 via gateway    ${T_502:-not seen}"
    echo "backend Unhealthy        ${T_UNHEALTHY:-not seen}"
    if [[ -n "${MANUAL:-}" ]]; then
      echo
      echo "## Manual response steps (first poll that showed each step in Azure; polls every ~15-30 s)"
      echo "snapshot exists          ${T_M_SNAPSHOT:-not seen}"
      echo "NIC on isolation NSG     ${T_M_NSG:-not seen}"
      echo "tag SecurityStatus       ${T_M_TAG:-not seen}"
      echo "comment on incident      ${T_M_COMMENT:-not seen}"
      echo "Discord message          (posted by the operator; time reported in chat, see Run log)"
    fi
    echo
    echo "## Incidents of this run (T0 .. T0+45 min) (Defender sync: providerName / providerIncidentId / incidentUrl)"
    while IFS='|' read -r num created sev rule guid title <&3; do
      az rest --method get -o json --url "https://management.azure.com$SI/incidents/$guid?api-version=2024-03-01" | pyj '
p = d["properties"]
print("#{} {} | {} | status {} | provider {} | providerIncidentId {} | alerts {}".format(p["incidentNumber"], p["title"], p["severity"], p["status"], p.get("providerName"), p.get("providerIncidentId"), p.get("additionalData", {}).get("alertsCount")))
print("   url", p.get("incidentUrl"))'
      echo "   entities:"
      az rest --method post -o json --url "https://management.azure.com$SI/incidents/$guid/entities?api-version=2024-03-01" | pyj '
for e in d.get("entities", []):
    p = e.get("properties", {})
    print("     ", e.get("kind"), p.get("address") or p.get("resourceId") or p.get("friendlyName"))'
      echo "   comments:"
      az rest --method get -o json --url "https://management.azure.com$SI/incidents/$guid/comments?api-version=2024-03-01" | pyj '
for c in sorted(d.get("value", []), key=lambda c: c["properties"]["createdTimeUtc"]):
    print("     ", c["properties"]["createdTimeUtc"], c["properties"]["message"].replace("\n", " / ")[:400])'
    done 3< <(incidents_since "$T0" "$T1")
    echo
    echo "## Playbook runs of this run (T0 .. T0+45 min) (which incident each run handled, key action times)"
    while IFS='|' read -r name start end status <&3; do
      echo "run $name  $start -> $end  $status"
      az rest --method get -o json --url "https://management.azure.com$PB_ID/runs/$name?api-version=2016-06-01" | pyj '
import urllib.request
link = d["properties"]["trigger"].get("outputsLink", {}).get("uri")   # SAS URL: read, never printed
if link:
    b = json.loads(urllib.request.urlopen(link).read().decode("utf-8"))["body"]
    print("   trigger: objectEventType {} | incident #{} | severity {}".format(b.get("objectEventType"), b["object"]["properties"].get("incidentNumber"), b["object"]["properties"].get("severity")))'
      az rest --method get -o json --url "https://management.azure.com$PB_ID/runs/$name/actions?api-version=2016-06-01" | pyj '
want = ("Validate", "b_Snapshot_OS_disk", "c_Isolate_NIC", "e_Verify_NIC", "e_Verify_snapshot", "Comment_high", "g_Notify_high", "Comment_medium", "g_Notify_medium", "Comment_rejected")
for a in sorted(d["value"], key=lambda a: a["properties"].get("startTime", "")):
    if a["name"] in want and a["properties"].get("status") != "Skipped":
        p = a["properties"]
        print("   {:<20} {} -> {}  {}".format(a["name"], p.get("startTime"), p.get("endTime"), p.get("status")))'
    done 3< <(runs_since "$T0" "$T1")
    echo
    if [[ -n "${MANUAL:-}" ]]; then
      echo "## Who responded"
      echo "Manual baseline: the automation rule stayed OFF (pre-flight checked enabled=false), so the playbook-run"
      echo "list above must be empty; every containment step was done by a person in the Azure and Defender portals."
    else
    echo "## Who started the playbook"
    echo "Proof that the automation rule (not a person) started each run:"
    echo " - this script never calls runPlaybook or the Logic App trigger; it only switches the automation rule on/off;"
    echo " - each run's trigger data (Microsoft_Sentinel_incident, objectEventType Create) names the incident it handled,"
    echo "   and each run started ~10-12 s after that incident was created (timeline above)."
    echo " - SentinelHealth (rows arrive ~5-10 min late; re-run --report if empty) records each automation-rule run"
    echo "   with the incident and the playbook RunId it started:"
    bash "$REPO_ROOT/infra/kql.sh" --json --timespan P2D "SentinelHealth
| where TimeGenerated between (datetime($T0) .. datetime($T1)) and SentinelResourceType == 'Automation rule'
| project TimeGenerated, Status, ExtendedProperties" | python -c '
import json, sys
sys.stdout.reconfigure(encoding="utf-8")
rows = json.loads(sys.stdin.buffer.read().decode("utf-8"))
for r in rows:
    e = r["ExtendedProperties"]; e = json.loads(e) if isinstance(e, str) else e
    print("     {} {} incident #{} -> playbook run {}".format(r["TimeGenerated"], r["Status"], e.get("IncidentNumber"),
          ", ".join(p["RunId"] for p in e.get("TriggeredPlaybooks", []))))
if not rows: print("     (no SentinelHealth rows yet)")' || echo "     (query failed)"
    fi
    echo
    echo "## Run log"
    cat "$RAW"
  } > "$OUT.tmp"
  # Mask our own laptop's IP(s) in this run's window (User-Agent ATDR-e2e; the ISP may change it between
  # runs) and the gateway's IP; then, as a safety net, any other IPv4 address to its first two octets.
  local testers ip
  local sedargs=(-e "s/${PIP//./\.}/<appgw-public-ip>/g")
  testers="$(bash "$REPO_ROOT/infra/kql.sh" --json --timespan P30D "AGWAccessLogs
| where TimeGenerated between (datetime($T0) .. datetime($T1)) and UserAgent startswith 'ATDR-e2e'
| distinct ClientIp" | python -c 'import json,sys; print(" ".join(r["ClientIp"] for r in json.load(sys.stdin)))')"
  for ip in $testers; do sedargs+=(-e "s/${ip//./\.}/<tester-ip>/g"); done
  sed "${sedargs[@]}" "$OUT.tmp" |
    sed -E 's/\b([0-9]{1,3}\.[0-9]{1,3})\.[0-9]{1,3}\.[0-9]{1,3}\b/\1.x.x/g' |
    sanitize > "$OUT"
  rm -f "$OUT.tmp"
  echo "report written: $OUT"
}

if [[ "$MODE" == "--report" ]]; then report; exit 0; fi
if [[ "$MODE" == "--close" ]]; then  # after rollback: close every open incident from our two rules
  open_atdr_incidents | while IFS='|' read -r num guid; do
    echo "[$(utc_now)] closing incident #$num: $(close_incident "$guid" </dev/null)" | tee -a "$RAW"
  done
  exit 0
fi

preflight() {  # everything must be in the normal state before any traffic is sent
  # An open ATDR incident would absorb this run's alerts (grouping by IP), so no new incident -> no playbook.
  local open pre status inc nsg s h auto
  open="$(open_atdr_incidents | cut -d'|' -f1 | tr '\n' ' ')"
  [[ -z "${open// }" ]] || { log "ABORT: open ATDR incidents: $open- close them first: bash tests/e2e_run.sh <previous run> --close"; exit 1; }
  pre="$(vm_state)"; IFS='|' read -r status inc nsg <<<"$pre"
  [[ -z "$status" && "$nsg" == "$NSG_BACKEND" ]] || { log "ABORT: VM not in normal state ($pre); run response/rollback.sh first"; exit 1; }
  s="$(site_status)"; h="$(backend_health)"
  auto="$(bash "$REPO_ROOT/detection-live/automation-rule.sh" status | sed 's/.*enabled=//')"
  log "pre-flight: no open ATDR incidents, VM tags clean, NIC on $nsg, GET / -> $s, backend health $h, automation rule enabled=$auto"
  [[ "$s" == "200" && "$h" == "Healthy" ]] || { log "ABORT: site not healthy"; exit 1; }
  [[ "$auto" == "false" ]] || { log "ABORT: automation rule is on between sessions; turn it off first"; exit 1; }
}

attack() {
  T0="$(utc_now)"
  log "T0 attack start"
  python - "$(winpath "$REPO_ROOT/tests")" "$URL" "$UA" <<'EOF' | tee -a "$RAW"
import os, sys, time
sys.path.insert(0, sys.argv[1])
import waf_tests as w
w.USER_AGENT = sys.argv[3]
run = w.Run(sys.argv[2], os.devnull)
ATTACKS = [  # standard, documented WAF test strings
    "' OR 1=1--",
    "1' UNION SELECT username, password FROM users--",
    "<script>alert('xss')</script>",
    "<img src=x onerror=alert(1)>",
    "<svg/onload=alert(1)>",
]
for a in ATTACKS:
    print("[{}] attack search={!r} -> HTTP {}".format(w.utc_now(), a, run.get("/products", {"search": a})), flush=True)
t = time.monotonic()
st = [run.get("/products", {"search": "lock"}) for _ in range(w.BURST)]
first = next((i + 1 for i, s in enumerate(st) if s == 403), None)
print("[{}] burst of {} in {:.1f}s: 200s={} 403s={} first 403 at #{}".format(
    w.utc_now(), len(st), time.monotonic() - t, st.count(200), st.count(403), first), flush=True)
print("[{}] burst statuses: {}".format(w.utc_now(), " ".join(map(str, st))), flush=True)
EOF
  T_ATTACK_END="$(utc_now)"
  log "attack end; now waiting for Sentinel (logs ~4 min + rule schedule 5 min)"
}

save_state() {
  {
    printf 'T0=%s\nT_ATTACK_END=%s\nT_ISOLATED=%s\nT_502=%s\nT_UNHEALTHY=%s\n' \
      "$T0" "$T_ATTACK_END" "${T_ISOLATED:-}" "${T_502:-}" "${T_UNHEALTHY:-}"
    printf 'MANUAL=%s\nT_M_SNAPSHOT=%s\nT_M_NSG=%s\nT_M_TAG=%s\nT_M_COMMENT=%s\n' \
      "${MANUAL:-}" "${T_M_SNAPSHOT:-}" "${T_M_NSG:-}" "${T_M_TAG:-}" "${T_M_COMMENT:-}"
  } > "$STATE"
}

high_incident_comments() {  # number of comments on the High incidents created since T0
  local total=0 n guid
  while IFS='|' read -r _ _ sev _ guid _ <&3; do
    [[ "$sev" == "High" ]] || continue
    n="$(az rest --method get -o json --url "https://management.azure.com$SI/incidents/$guid/comments?api-version=2024-03-01" |
         pyj 'print(len(d.get("value", [])))')"
    total=$(( total + n ))
  done 3< <(incidents_since "$T0")
  echo "$total"
}

case "$MODE" in
  --preflight)  # dry check only: no traffic, automation rule untouched
    : > "$RAW"; log "dry pre-flight $N (no traffic)"; preflight; log "pre-flight OK"; exit 0 ;;
  --watch)  # re-attach to an automated run whose watcher died: same T0, no new traffic
    # shellcheck disable=SC1090
    source "$STATE"
    log "re-attached watcher for E2E run $N (T0 $T0); no new traffic sent"
    trap 'bash "$REPO_ROOT/detection-live/automation-rule.sh" off | tee -a "$RAW"' EXIT
    bash "$REPO_ROOT/detection-live/automation-rule.sh" on | tee -a "$RAW" ;;
  --manual)  # manual-response baseline: automation rule stays OFF, a person contains the VM in the portal
    : > "$RAW"; MANUAL=1
    log "MANUAL baseline $N against our gateway <appgw-public-ip>; automation rule stays OFF"
    preflight; attack; save_state ;;
  run)
    : > "$RAW"
    log "E2E run $N against our gateway <appgw-public-ip>; VM $VM_NAME"
    preflight
    # The automation rule is on only while this script runs, off again on any exit.
    trap 'bash "$REPO_ROOT/detection-live/automation-rule.sh" off | tee -a "$RAW"' EXIT
    bash "$REPO_ROOT/detection-live/automation-rule.sh" on | tee -a "$RAW"
    attack; save_state ;;
  *) echo "unknown mode $MODE" >&2; exit 2 ;;
esac

# --- watch ----------------------------------------------------------------------------------------
T_ISOLATED=""; T_502=""; T_UNHEALTHY=""; seen_inc=""; seen_runs=""
T_M_SNAPSHOT=""; T_M_NSG=""; T_M_TAG=""; T_M_COMMENT=""
START=$SECONDS
LIMIT=2100; [[ -n "${MANUAL:-}" ]] && LIMIT=2700   # manual: allow 45 min
while (( SECONDS - START < LIMIT )); do
  incs="$(incidents_since "$T0")"; runs="$(runs_since "$T0")"
  [[ "$incs" != "$seen_inc" ]] && { log "incidents since T0:"; sed 's/^/    #/' <<<"$incs" | tee -a "$RAW"; seen_inc="$incs"; }
  [[ "$runs" != "$seen_runs" ]] && { log "playbook runs since T0${MANUAL:+ (UNEXPECTED in manual mode)}:"; sed 's/^/    /' <<<"$runs" | tee -a "$RAW"; seen_runs="$runs"; }
  st="$(vm_state)"; IFS='|' read -r status inc nsg <<<"$st"
  if [[ -n "${MANUAL:-}" ]]; then  # record when Azure first shows each manual step
    if [[ -z "$T_M_SNAPSHOT" ]]; then
      snap="$(az snapshot list -g "$RG" --query "[0].name" -o tsv | tr -d '\r')"
      [[ -n "$snap" ]] && { T_M_SNAPSHOT="$(utc_now)"; log "MANUAL step seen: snapshot $snap"; }
    fi
    [[ -z "$T_M_NSG" && "$nsg" == "$NSG_ISOLATION" ]] && { T_M_NSG="$(utc_now)"; log "MANUAL step seen: NIC on $nsg"; }
    [[ -z "$T_M_TAG" && "$status" == "Quarantined" ]] && { T_M_TAG="$(utc_now)"; log "MANUAL step seen: tag SecurityStatus=$status IncidentNumber=$inc"; }
    if [[ -z "$T_M_COMMENT" && -n "$incs" ]] && (( $(high_incident_comments) > 0 )); then
      T_M_COMMENT="$(utc_now)"; log "MANUAL step seen: comment on the High incident"
    fi
  fi
  if [[ -z "$T_ISOLATED" && "$status" == "Quarantined" && "$nsg" == "$NSG_ISOLATION" ]]; then
    T_ISOLATED="$(utc_now)"; log "ISOLATION VERIFIED: SecurityStatus=$status IncidentNumber=$inc NIC NSG=$nsg"
  fi
  if [[ "$nsg" == "$NSG_ISOLATION" && -z "$T_502" ]]; then
    s="$(site_status)"; log "GET / via gateway -> $s"
    [[ "$s" == "502" ]] && T_502="$(utc_now)"
  fi
  if [[ "$nsg" == "$NSG_ISOLATION" && -z "$T_UNHEALTHY" ]]; then
    h="$(backend_health)"; log "backend health -> $h"
    [[ "$h" == "Unhealthy" ]] && T_UNHEALTHY="$(utc_now)"
  fi
  save_state
  both_rules=$(grep -c -e '|repeated-blocks|' -e '|rate-limit|' <<<"$incs" || true)
  busy=$(grep -c -E '\|(Running|Waiting)$' <<<"$runs" || true)
  manual_done=yes
  [[ -n "${MANUAL:-}" && ( -z "$T_M_SNAPSHOT" || -z "$T_M_COMMENT" ) ]] && manual_done=""
  if [[ -n "$T_ISOLATED" && -n "$T_502" && -n "$T_UNHEALTHY" && "$busy" == 0 && -n "$manual_done" ]] &&
     { (( both_rules >= 2 )) || (( SECONDS - START > 900 )); }; then
    log "all checks done"; break
  fi
  sleep 15
done
[[ -n "$T_ISOLATED" ]] || log "TIMEOUT: isolation not seen within $(( LIMIT / 60 )) min"
report
