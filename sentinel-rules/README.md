# Sentinel security monitoring module

This is a portal-first, safe-to-review module for Microsoft Sentinel and
Defender for Cloud. It contains KQL source files, inline test data, a normalized
alert contract, and setup/response instructions. It does not deploy resources,
enable paid plans, or call external systems.

## Current evidence status

| Capability | Status |
| --- | --- |
| Repository baseline | Verified: no previous README or implementation files were present. |
| Azure subscription and workspace | Verified read-only on 2026-10-20: active subscription is Azure for Students; `law-threat-detection-aayush` exists in Korea Central, provisioning succeeded, Analytics workspace plan, 30-day retention. |
| Microsoft Sentinel | Verified: the workspace has a `Microsoft.SecurityInsights/onboardingStates/default` resource and a Sentinel resource. The portal-reported trial end date (2026-11-20) was supplied by the owner, not independently verified by CLI. |
| Candidate table schemas | Verified as provisioned: `SigninLogs`, `SecurityAlert`, `AGWFirewallLogs`, and `AzureActivity` are present as Analytics tables. Table existence does not prove a connector is active. |
| Ingested records | Checked with read-only KQL over the last 30 days: zero rows in `SigninLogs` and `SecurityAlert`; no rows returned for `AGWFirewallLogs` or `AzureActivity`. |
| Azure Activity export | Owner-approved correction: the ineffective resource-group assignment was replaced with a subscription-scope assignment. The new identity has Monitoring Contributor at subscription scope and Log Analytics Contributor on the workspace. Remediation `remediate-azure-activity-log` is still `Evaluating`; no subscription diagnostic setting or `AzureActivity` rows were observed yet. |
| Defender for Cloud findings | Read-only subscription assessment list returned 16 posture assessments, 7 with `Unhealthy` status. Defender security-alert list returned 0 alerts. An unhealthy recommendation is a real posture finding, not a Sentinel alert or incident. |
| Existing analytics rules | No `Microsoft.SecurityInsights/alertRules` resources found in the project resource group. |
| Data connectors | No `Microsoft.SecurityInsights/dataConnectors` resources were returned by the subscription-wide read-only ARM listing. Confirm the connector status in the portal; this listing is not proof that no source integration exists by another mechanism. |
| Detection query / analytics alert / incident | Query syntax validated against actual workspace tables; no live source rows available. The Azure Activity query matched zero live groups; no live query result, alert, or incident was produced. |
| Source-independent demo queries | Three standalone `datatable` demos were executed in the workspace Logs query API. Each returned the documented simulated result; this was query output only, not a Sentinel alert, incident, or Logic App execution. |
| Sample events and alert examples | Simulated only. No sample is presented as a real Azure event or resource. |
| WAF and Logic Apps integration | Pending teammate-owned resources, their tenant/workspace choices, and authorized access. |

## Contents

- [`alert-contract/normalized-alert.schema.json`](./alert-contract/normalized-alert.schema.json) — response playbook contract.
- [`samples/normalized-alerts.json`](./samples/normalized-alerts.json) — four simulated severity examples; all resource IDs are `null`.
- [`samples/waf-firewall-events.json`](./samples/waf-firewall-events.json) — synthetic WAF rows using documented `AGWFirewallLogs` fields.
- [`samples/demo-normalized-alert.json`](./samples/demo-normalized-alert.json) and [`samples/demo-simulated-response.json`](./samples/demo-simulated-response.json) — normalized simulated alert and non-executing response illustration.
- [`queries/`](./queries/) — live-source detections plus three standalone `datatable` demo queries.
- [`tests/`](./tests/) — inline, safe KQL fixtures for the detection patterns without live source events.
- [`tests/test_artifacts.py`](./tests/test_artifacts.py) — local standard-library checks for contract, fixture, and query-file consistency.
- [`docs/onboarding.md`](./docs/onboarding.md) — workspace, connectors, analytics rules, and incident verification.
- [`docs/defender-for-cloud.md`](./docs/defender-for-cloud.md) — scoped Defender setup and cost notes.
- [`docs/integration.md`](./docs/integration.md) — WAF and Logic Apps integration agreements.
- [`docs/runbook-and-cost.md`](./docs/runbook-and-cost.md) — costs, safety, troubleshooting, cleanup, and evidence.
- [`docs/demo.md`](./docs/demo.md) — short demonstration script.
- [`docs/simulation-demo.md`](./docs/simulation-demo.md) — exact portal steps and expected output for the source-independent demo.
- [`docs/checklist.md`](./docs/checklist.md) — deliverable checklist and validation evidence.

## Quick start

1. Read the safety and permission requirements in [`docs/onboarding.md`](./docs/onboarding.md).
2. Get explicit owner approval before enabling Sentinel, configuring diagnostic
   settings, ingesting logs, or enabling any Defender workload plan.
3. Confirm with Person 1 the actual WAF SKU, diagnostic destination, table mode,
   and one redacted event. Do not assume `AGWFirewallLogs` is already populated.
4. Run the local checks from this directory:

   ```sh
   python3 -m unittest discover -s tests -v
   ```

5. To test query logic independently, paste an inline fixture from `tests/`
   into the workspace Logs editor. It uses only an inline `datatable`; it will
   not create an alert or incident.
   For the presentation-ready source-independent walkthrough, follow
   [`docs/simulation-demo.md`](./docs/simulation-demo.md).
6. For live alert/incident verification, follow [`docs/onboarding.md`](./docs/onboarding.md)
   and only use a WAF that the team owns and is authorized to test.

## Query validation boundary

The documented table names and columns are based on Microsoft Learn and
workspace schema inventory. Queries were used read-only to check table data,
and production queries were successfully parsed/executed against their real
tables with zero rows returned. This validates query syntax/schema, not
detection logic against live source events. Inline fixture queries are tested
separately with simulated data. The Entra single-failure demo query requires
an approved Entra connector and a dedicated test account. The WAF rate-limit
query additionally requires Person 1 to confirm the actual custom rule ID/name
that represents rate limiting. The Azure Activity repeated-failure query also
requires subscription Activity Log export to be configured; the current policy
assignment is now subscription-scoped, but its approved remediation is still
evaluating and no setting or rows are verified. The Azure Activity query's
synthetic fixture returned one expected group of five failed operations; this
is simulated output, not a live detection. The owner approved replacing the
resource-group policy assignment with a subscription-scoped assignment and
granting its new identity the two roles required by the built-in definition.
The remediation task is still evaluating; its diagnostic setting and log
ingestion are not yet verified. The three standalone presentation queries
were separately executed against in-memory synthetic tables and returned their
expected counts. The four orphaned role-assignment records for
the deleted identity were removed after approval; the new identity's two
required role assignments remain verified.

For a genuine finding that can be demonstrated now without changing the
subscription, open **Defender for Cloud > Recommendations** and review an
existing unhealthy posture assessment. Do not describe it as a Sentinel alert;
the subscription alert list and workspace `SecurityAlert` query both returned
zero alerts.
