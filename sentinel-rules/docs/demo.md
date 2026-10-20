# Short demonstration script

Target duration: 4–6 minutes. Keep all resource identifiers, user names, and
source IPs redacted in the report.

1. **Set expectations (30 seconds).** Explain that samples are synthetic and
   that live Sentinel behavior requires an approved workspace and source logs.
2. **Show the contract (45 seconds).** Open
   `alert-contract/normalized-alert.schema.json` and one payload from
   `samples/normalized-alerts.json`. Point out `simulation: true`,
   `resource_id: null`, and null Sentinel identifiers.
3. **Test KQL without Azure data (60 seconds).** Paste
   `tests/waf-query-test.kql` into an authorized workspace Logs editor if one
   exists. Expected result: exactly one row for `192.0.2.20`, five blocked
   events, five distinct transactions. If no workspace exists, show the query
   file and run local artifact tests instead. This KQL query creates no alert.
4. **Explain live WAF detection (60 seconds).** Show
   `queries/waf-repeated-blocks.kql`, its `AGWFirewallLogs` dependency, time
   window, threshold, and false-positive caveats.
5. **Walk onboarding (60 seconds).** Show the diagnostics setting, connector,
   analytics-rule portal settings, and validation path in
   `docs/onboarding.md`. Do not claim deployment unless it was performed and
   captured by the authorized owners.
6. **Show integration handoff (60 seconds).** Review required WAF facts and
   explain that the Logic App trigger's native payload must be mapped from a
   real run history to the project schema.
7. **Close (30 seconds).** State what is verified, simulated, pending, costs,
   and cleanup steps using `docs/checklist.md` and
   `docs/runbook-and-cost.md`.

If approved live resources and a real WAF test exist, replace step 3 with a
safe request to the team's own test endpoint and show its real alert/incident.
Do not generate malicious traffic or test systems outside the team's scope.
