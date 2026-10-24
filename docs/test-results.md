# Test results

All results below are from the live deployment in resource group `rg-atdr`
(Central India), 22–24 October 2026. Times are UTC. Every value comes from a
file in [`evidence/`](../evidence/), with subscription/tenant IDs and IP
addresses masked. "Verified" means the result was read back from Azure; nothing
here is simulated.

## 1. Headline comparison

| | Run 1 (automated) | Run 2 (automated) | Manual baseline |
|---|---|---|---|
| T0: attack sent | 23 Oct 21:32:44 | 23 Oct 22:45:31 | 24 Oct 23:16:13 |
| High incident created | 21:38:26 (+5:42) | 22:53:11 (+7:40) | 23:23:13 (+7:00) |
| Response started | 21:38:36: playbook, **+10 s** after incident | 22:53:20: playbook, **+8 s** | when the operator saw the incident in Defender |
| NIC moved to isolation NSG | 21:38:40.7 (+15 s) | 22:53:25.3 (+14 s) | 23:30:40 (**+7:27**) |
| Isolation verified (NIC + `SecurityStatus=Quarantined`) | 21:38:57 (**+31 s**) | 22:53:45 (**+34 s**) | 23:40:35 (**+17:22**) |
| Playbook duration | 10.3 s | 12.1 s | n/a; operator stopwatch **11:09** of hands-on work |
| Site returns 502 via gateway | 21:42:31 | 22:57:23 | 23:34:36 |
| Backend health Unhealthy | 21:42:44 | 22:57:36 | 23:34:49 |
| T0 → isolation verified | 6:13 | 8:14 | 24:22 |
| Evidence | `06-e2e-run1.txt` | `06-e2e-run2.txt` | `06-e2e-runbaseline.txt` |

`+m:ss` is the time since the High incident was created.

**Reading the table**

- **Response after detection:** about 30 seconds automated versus about 17
  minutes by hand. The automated response is roughly 30 times faster, and the
  manual figure is a best case: the operator was waiting for the incident,
  knew the steps, and had every portal tab open.
- **Detection itself** (attack → incident) took 5.5–8 minutes in every run and is
  the same for both. It is about 4 minutes of Log Analytics ingestion plus up
  to 5 minutes until the next scheduled run of the analytics rule.
- **502 / Unhealthy** arrive about 3.5–4 minutes after isolation. The isolation
  NSG drops packets silently, so each health probe waits its full 30-second
  timeout, and the gateway needs 3 failed probes before it marks the backend
  Unhealthy. Until then, page requests hang.
- **Medium incidents** (rate-limit rule) were created alongside each High
  incident. The playbook commented and notified only (runs of 7–8 s), as designed.

## 2. What was verified in each automated run

| Check | Run 1 | Run 2 |
|---|---|---|
| 5 SQLi/XSS test strings → HTTP 403 | 5/5 | 5/5 |
| 50-request burst → RateLimitDemo 403s | 17 (first at #34) | 17 (first at #34) |
| High + Medium incidents created by the two analytics rules | #4 + #3 | #5 + #6 |
| Incidents synced to the Defender portal (provider "Microsoft XDR") | Defender 2 + 1 | Defender 4 + 3 |
| Entities on both incidents: IP and AzureResource (atdr-vm-backend) | yes | yes |
| Playbook started by the automation rule, not by a person (see below) | yes | yes |
| Snapshot `atdr-snap-<n>` Succeeded | atdr-snap-4 | atdr-snap-5 |
| NIC on `atdr-nsg-isolation`, VM tagged Quarantined / IncidentNumber / OriginalNsg | yes | yes |
| Incident comment written by the playbook | yes | yes |
| Discord message received | yes (both) | yes |
| 502 through the gateway, backend Unhealthy | yes | yes |
| Rollback → 200 + Healthy | 81 s | 84 s |

**How we know the automation rule started the playbook.**
- `tests/e2e_run.sh` never calls the playbook; it only switches the automation rule on and off.
- Each run's trigger data (`Microsoft_Sentinel_incident`, `objectEventType: Create`) names the incident it
  handled, and each run started 8–12 seconds after that incident was created.
- **Run 2:** Sentinel's health log (`SentinelHealth`) records the automation rule "ATDR – Run containment
  playbook on ATDR incidents" firing on *Incident Created* for #6 and #5, and names the exact playbook
  RunIds it started (`evidence/06-sentinelhealth-automation.txt`).
- Run 1 is not in the health log: monitoring had been enabled at 21:28, but its first rows only arrived at 22:12.
- The Azure Activity Log does not record runPlaybook calls, so it cannot be used (checked against an earlier
  manual call as a positive control).

## 3. Manual baseline in detail (24 Oct)

Same attack as the automated runs, with the automation rule **off**. The
operator did the playbook's steps by hand in the Azure and Defender portals.
`tests/e2e_run.sh baseline --manual` recorded when Azure first showed each step
(polling every 15–30 s).

| Step | Seen in Azure | Since incident created |
|---|---|---|
| High incident created (Sentinel #11, Defender 9) | 23:23:13 | 0:00 |
| 1. Snapshot `atdr-snap-manual` | 23:29:00 | 5:47 |
| 2. NIC → `atdr-nsg-isolation` | 23:30:40 | 7:27 |
| 3. Comment on the incident | 23:35:14 | 12:01 |
| 4. Tags `SecurityStatus=Quarantined`, `IncidentNumber=9` | 23:40:34 | 17:21 |
| 5. Discord message | reported by the operator, about 23:42 | about 19 |
| Operator stopwatch (incident seen in Defender → Discord posted) | | **11:09** |

No playbook ran during the baseline (the run list since T0 is empty).

## 4. WAF tests T1–T6 (`tests/waf_tests.py`)

| Test | Expected | Result (23 Oct 16:57, `evidence/04-waf-tests-run1.txt`) |
|---|---|---|
| T1 `GET /` | 200 | 200 PASS |
| T2 `GET /health` | 200 | 200 PASS |
| T3 search `' OR 1=1--` | 403 | 403 PASS (rule 949110) |
| T4 search `<script>alert('xss')</script>` | 403 | 403 PASS (rule 949110) |
| T5 burst | later requests 403 (RateLimitDemo) | 30 requests: 4 blocks; the file says FAIL under the first, too strict criterion, and the corrected check passes (see below) |
| T6 after 70 s | 200 | 200 PASS |

**T5 and the two gateway instances.** Autoscale cannot go below 2 instances
(Azure rejects a maximum of 1: valid range 2–125), and each instance counts the
20-per-minute limit separately. A 30-request burst was split 15/15 and produced
4 blocks once and **0** blocks in a rerun (`evidence/04-waf-t5-rerun.txt`). T5
now sends **50** requests (about 25 per instance), and every 50-request burst
since then produced 15–19 blocks.

## 5. Detection queries against real data (Phase 5)

`evidence/05-detection-queries.txt`. The live queries, replayed over 23 Oct in
15-minute windows, would have raised:

| Window | Client | Repeated blocks (High, ≥ 5) | Rate limit (Medium, ≥ 3) |
|---|---|---|---|
| 16:45 | our tester | 6 blocked transactions | 4 RateLimitDemo blocks |
| 19:15 | outside client 94.154.x.x | 5 | — |
| 20:15 | internet scanner 172.232.x.x (289 requests) | 231 | 226 |

Thresholds: repeated blocks kept at Aayush's **5**. Rate limit lowered from
**10 → 3**, because one burst produced at most 4 blocks at the time, so 10 could
never fire for our test traffic.

## 6. Real internet scanners (automation rule off)

`evidence/06-scanner-incidents.txt`. Between test sessions the automation rule
is switched off, so real incidents are recorded but the VM is not isolated
unattended.

| Incidents | When | Client | Traffic | Outcome |
|---|---|---|---|---|
| #7 Medium, #8 High | 24 Oct 01:13 | 124.158.x.x (`libredtail-http`) | 49 requests in 31 s, 47 blocked; PHP remote-code-execution probes (`phpunit/eval-stdin.php`, `allow_url_include`) | no playbook run; closed TruePositive / SuspiciousActivity |
| #9 High, #10 Medium | 24 Oct 22:48 | 45.138.x.x (`l9explore`) | 90 requests in 25 s, 88 blocked; secret hunting (`/.env`, `/.git/config`) | no playbook run; closed TruePositive / SuspiciousActivity |

Before the analytics rules existed, a third scanner (172.232.x.x, 23 Oct
20:21) sent 289 requests and 231 were blocked. Had the rules and automation
been on, every one of these would have isolated the VM. That is the limitation
discussed in [`how-it-works.md`](./how-it-works.md#limitations).

## 7. Unit and component tests

| Test | Result | Evidence |
|---|---|---|
| `tests/test_app.py`, 15 Flask unit tests | 15 passed | `02-unit-tests.txt` |
| Web app on the VM (`/health` 200 via run-command) | pass | `02-webapp-verify.txt` |
| Playbook High test (API incident #1) | Succeeded in 13 s, isolation verified | `03-high-run.txt` |
| Playbook Low test (API incident #2) | Rejected, no action, comment written | `03-low-rejection.txt` |
| Rollback, then a single-call tag removal with dry run | restored | `03-rollback.txt`, `03-rollback-single-call-test.txt` |

## 8. Challenges faced, and how we solved them

1. **Windows tooling.** Git Bash rewrote Azure resource paths
   (`/subscriptions/...` became `C:/Program Files/Git/...`), and the Azure CLI
   mangled non-ASCII characters (the en dash in rule names). Fixed with
   `MSYS_NO_PATHCONV`, and by building every JSON body in Python with ASCII
   escapes.
2. **VM size and SSH key.** `Standard_B1s` was not offered to the subscription,
   so we used `Standard_B2ats_v2`. `--generate-ssh-keys` failed on Windows, so a
   key is generated with `ssh-keygen` first. The VM has no public IP; access is
   only via `az vm run-command`.
3. **Rate-limit rule.** Azure rejected `RemoteAddr` as a match variable in a
   rate-limit rule. Rule fallback: match `RequestUri` begins with `/`, grouped
   by client address, 20 per minute.
4. **Two gateway instances.** The rate limit is counted per instance and
   autoscale cannot go below 2, which made a 30-request burst unreliable. We
   raised it to 50, corrected the T5 pass criterion, and lowered the rate-limit
   detection threshold from 10 to 3.
5. **Defender portal onboarding.** With `atdr-law` onboarded to the Defender
   portal, incidents created through the API do not appear in Defender, and
   clicking "Run playbook" did not start a run. For the Phase 3 tests we used
   the Sentinel `runPlaybook` API; real analytics-rule incidents do sync
   (provider "Microsoft XDR"). "Update Logic Apps permissions" showed a red X,
   but the Azure Security Insights service principal already had Microsoft
   Sentinel Automation Contributor on rg-atdr, and the automation rule worked.
6. **Alert grouping swallowed a run.** Run 2's first attempt created no incident:
   run 1's incidents were still open, and the rules group alerts by IP, so the
   new alerts were added to the old incidents and the "incident created"
   automation never fired. Fix: close each run's incidents after rollback
   (`e2e_run.sh <n> --close`), and pre-flight refuses to start while an ATDR
   incident is open.
7. **Real scanners.** With automation always on, internet scanners would isolate
   the VM unattended (four incidents in one day). The automation rule is now
   switched off between sessions (`detection-live/automation-rule.sh`), and
   rule suppression (15 min) stops a burst re-isolating the VM right after a rollback.
8. **Slow 502.** Isolation is instant, but the gateway needs 3 timed-out probes
   (about 3.5–4 min) before it shows 502 / Unhealthy. This is documented for the
   demo rather than tuned away.
9. **Proof of who started the playbook.** A manual run and an automated run look identical in the run
   history, and the Activity Log does not record runPlaybook calls. Sentinel health monitoring only started
   delivering rows about 45 minutes after it was enabled, which covers run 2 but not run 1. Run 1's proof is
   the trigger data plus the 10 s gap (section 2).
10. **Test harness.** One watcher process was cut off by a broken output pipe
    during run 2; it was re-attached with `e2e_run.sh 2 --watch` (same T0, no
    new traffic), and the script now logs the exact failing command on any error.
    The tester's public IP also changed overnight, so evidence masks it by
    User-Agent rather than by a fixed address.
