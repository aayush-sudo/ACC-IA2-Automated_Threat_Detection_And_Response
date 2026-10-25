# Screenshots checklist

Take these for the report. Before sharing, crop or blur the subscription ID,
tenant ID, e-mail addresses and your own public IP.
☐ = still to take on recording day; the rest were taken during the build.

## Phase 1: foundation
- [x] rg-atdr → Overview: resource list, all tagged `Project=ATDR`.
- [x] atdr-vnet → Subnets: snet-appgw 10.10.1.0/24, snet-backend 10.10.2.0/24.
- [x] atdr-nsg-backend / atdr-nsg-isolation → Inbound security rules (isolation: Deny-All both ways).
- [x] atdr-vm-backend → Overview: no public IP, size Standard_B2ats_v2.
- [x] atdr-law → Microsoft Sentinel enabled.

## Phase 2: web app
- [x] Terminal: `/health` returned 200 via run-command (`evidence/02-webapp-verify.txt`).
- [x] Terminal: 15 unit tests passed.

## Phase 3: playbook
- [x] atdr-playbook-contain → Logic app designer (the action list).
- [x] atdr-playbook-contain → Identity: system-assigned on; Azure role assignments (4 roles on rg-atdr).
- [x] Run history: the High test run with green actions, and the Low run "Rejected".
- [x] VM → Tags (Quarantined) and NIC → NSG atdr-nsg-isolation during the High test; snapshot atdr-snap-1.
- [x] Discord message from the High test.
- [x] After rollback: NIC back on atdr-nsg-backend, tags clean, no snapshot.

## Phase 4: WAF
- [x] atdr-wafpolicy → Overview (Prevention), Managed rules (DRS 2.1), Custom rules (RateLimitDemo: 20/min, RequestUri begins with /).
- [x] atdr-appgw → Overview (WAF V2, Running), Backend health (Healthy), Web application firewall (policy attached).
- [x] atdr-appgw → Diagnostic settings → atdr-diag-appgw (Resource specific → atdr-law).
- [x] Browser: the demo portal, and the 403 page for `/products?search=' OR 1=1--`.
- [x] atdr-law → Logs: `AGWFirewallLogs | summarize count() by Action, RuleId`; `AGWAccessLogs | summarize count() by HttpStatus, InstanceId`.

## Phase 5: detection
- [x] Defender → Microsoft Sentinel → Configuration → Analytics: both ATDR rules Enabled.
- [x] Repeated-blocks rule → Set rule logic (query, 5 min / 15 min) and entity mapping (IP, Azure resource).
- [x] Repeated-blocks rule → Incident settings (grouping by IP).
- [x] Rate-limit rule query (`RateLimitDemo`, `>= 3`).
- [x] Configuration → Automation: the automation rule with its condition and playbook action.
- [x] atdr-law → Logs: 24-hour replay query (`detection-live/test-queries.sh`) showing the windows that would alert.

## Phase 6: end-to-end (run 1; run 2 key shots only)
- [x] Defender → Incidents: High + Medium ATDR incidents.
- [x] Incident → Assets: IP + atdr-vm-backend. Activity log: playbook comment.
- [x] atdr-playbook-contain → Runs history: two automatic runs; the High run's green steps.
- [x] Discord: High containment and Medium notification messages.
- [x] VM → Tags (Quarantined, IncidentNumber, OriginalNsg); VM → Networking (atdr-nsg-isolation).
- [x] rg-atdr → Snapshots: atdr-snap-4.
- [x] atdr-appgw → Backend health: **Unhealthy**. Browser: **502 Bad Gateway**.
- [ ] Optional: Defender → Incidents showing the four closed scanner incidents (TruePositive).
- [ ] Optional: atdr-law → Logs, `SentinelHealth | where SentinelResourceType == "Automation rule"` (run 2's two rows: proof that the automation rule started the playbook).

## Recording day (`docs/demo-script.md`: Person 1 by Anthony, Person 3 by the teammate)
- [ ] Teammate's terminal: `waf_tests.py --attack` output (the 403 lines, the burst line, `OK`).
- [ ] Anthony's terminal: `tests/e2e_run.sh p3 --watch-only` stages (incident, playbook run, isolation verified, 502, Unhealthy).
- [ ] Defender incident page of the recorded run (entities and comment).
- [ ] Playbook run of the recorded run (green steps).
- [ ] 502 page and Backend health Unhealthy.
- [ ] After rollback: site 200 and backend Healthy.
- [ ] After `infra/cleanup.sh` (step 1): rg-atdr resource list without atdr-appgw / atdr-pip-appgw.
