# Demo running order (final)

Total **≤ 8:00**. Three recordings, edited together in this order (if Aayush's part
runs longer than 2:30, shorten segment 3's narration over the waiting):

| # | Who | Part | Target | How it is recorded |
|---|---|---|---|---|
| 1 | Anthony | Person 1: introduction, web app, WAF | ~2:30 | live in the browser and portal, automation rule **off** |
| 2 | Aayush | Person 2: detection (Sentinel rules) | ~2:30 | already recorded |
| 3 | Third teammate | Person 3: automated response | ~3:00 | live from his own laptop with `waf_tests.py`; Anthony watches with `e2e_run.sh --watch-only` |

Cut the waiting in segment 3 in the edit: about 6–8 minutes from traffic to
incident, plus about 4 minutes from isolation to the 502.

## Constraints between the recordings

- **Segment 1 traffic:** keep it to **at most 4 blocked requests** (for example one
  SQL-injection and one XSS search in the browser) and no flood. That stays below
  both rules' thresholds (High ≥ 5 blocks, Medium ≥ 3 rate-limit blocks), so no
  incident is created. If segment 1 does trigger the rules, close its incidents
  (`bash tests/e2e_run.sh p1 --close`) and wait **15 minutes** after they were
  created before segment 3: each rule is suppressed for 15 minutes after it fires.
- **Before segment 3:** no open ATDR incidents (pre-flight checks this), VM normal,
  site 200 and backend Healthy.
- **Segment 3, step by step:**
  1. Anthony: `bash tests/e2e_run.sh p3 --watch-only`. It runs pre-flight, switches
     the automation rule on, sends no traffic, and prints each stage.
  2. Teammate: `python waf_tests.py http://<gateway-ip>/ --attack` once (about 2 s).
     The same 5 test strings + 50-request burst gave 20–24 blocked requests in all
     four automated runs, well above both thresholds. The last line should say `OK`.
  3. Incident (about 6–8 min) → playbook (about 10 s later) → VM isolated → 502 /
     Unhealthy (about 4 min later).
  4. Everything stays isolated until Anthony says "rollback". Then:
     `bash response/rollback.sh --delete-snapshot` and `bash tests/e2e_run.sh p3 --close`.
- Background for spoken lines and faculty questions: [`how-it-works.md`](./how-it-works.md),
  numbers in [`test-results.md`](./test-results.md).
