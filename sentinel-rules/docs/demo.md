# Short demonstration script

Target duration: 4–6 minutes. Keep all resource identifiers, user names, and
source IPs redacted in the report.

1. **Set expectations (30 seconds).** Explain that samples are synthetic and
   that live Sentinel behavior requires an approved workspace and source logs.
2. **Show the contract (45 seconds).** Open
   `alert-contract/normalized-alert.schema.json` and one payload from
   `samples/normalized-alerts.json`. Point out `simulation: true`,
   `resource_id: null`, and null Sentinel identifiers.
3. **Run the source-independent simulation (2 minutes).** Follow
   [`simulation-demo.md`](./simulation-demo.md) in the workspace Logs editor.
   Run the Azure Activity, WAF, and Entra demo queries one at a time. Each is a
   complete `datatable` query; expected counts and the spoken explanation are
   documented there. These are query results only and do not create a Sentinel
   alert, incident, or Logic App run.
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

For a real current Defender posture example, the subscription has unhealthy
assessment recommendations available to review in **Defender for Cloud >
Recommendations**. Label this as a posture finding; the checked Defender
security-alert list and Sentinel `SecurityAlert` table had zero alerts.

If approved live resources and a real WAF test exist, replace step 3 with a
safe request to the team's own test endpoint and show its real alert/incident.
Do not generate malicious traffic or test systems outside the team's scope.
