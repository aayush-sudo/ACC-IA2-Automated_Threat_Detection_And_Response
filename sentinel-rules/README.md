# Sentinel security monitoring module

This is a portal-first, safe-to-review module for Microsoft Sentinel and
Defender for Cloud. It contains KQL source files, inline test data, a normalized
alert contract, and setup/response instructions. It does not deploy resources,
enable paid plans, or call external systems.

## Current evidence status

| Capability | Status |
| --- | --- |
| Repository baseline | Verified: no previous README or implementation files were present. |
| Azure workspace discovery | Verified: the default Azure context returned zero Log Analytics workspaces. This does not prove that another tenant or subscription has none. |
| WAF table schema | Verified against Microsoft Learn for `AGWFirewallLogs`; no live workspace query was possible. |
| Entra sign-in table schema | Verified against Microsoft Learn for `SigninLogs`; this detection is conditional on connecting Entra ID sign-in logs. |
| Defender alert table schema | Verified against Microsoft Learn for `SecurityAlert`; Defender findings are not present in this workspace context. |
| Query execution / analytics alert / incident | Pending: requires an authorized, configured workspace and real ingested events. |
| Sample events and alert examples | Simulated only. No sample is presented as a real Azure event or resource. |
| WAF and Logic Apps integration | Pending teammate-owned resources, their tenant/workspace choices, and authorized access. |

## Contents

- [`alert-contract/normalized-alert.schema.json`](./alert-contract/normalized-alert.schema.json) — response playbook contract.
- [`samples/normalized-alerts.json`](./samples/normalized-alerts.json) — four simulated severity examples; all resource IDs are `null`.
- [`samples/waf-firewall-events.json`](./samples/waf-firewall-events.json) — synthetic WAF rows using documented `AGWFirewallLogs` fields.
- [`queries/`](./queries/) — WAF blocked-request, WAF rate-limit, conditional Entra sign-in, and Defender alert queries.
- [`tests/`](./tests/) — inline, safe KQL fixtures for the WAF, sign-in, and Defender query patterns without live source events.
- [`tests/test_artifacts.py`](./tests/test_artifacts.py) — local standard-library checks for contract, fixture, and query-file consistency.
- [`docs/onboarding.md`](./docs/onboarding.md) — workspace, connectors, analytics rules, and incident verification.
- [`docs/defender-for-cloud.md`](./docs/defender-for-cloud.md) — scoped Defender setup and cost notes.
- [`docs/integration.md`](./docs/integration.md) — WAF and Logic Apps integration agreements.
- [`docs/runbook-and-cost.md`](./docs/runbook-and-cost.md) — costs, safety, troubleshooting, cleanup, and evidence.
- [`docs/demo.md`](./docs/demo.md) — short demonstration script.
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

5. To test query logic independently, paste `tests/waf-query-test.kql` into a
   workspace Logs editor. It uses only an inline `datatable`; it will not create
   an alert or incident.
6. For live alert/incident verification, follow [`docs/onboarding.md`](./docs/onboarding.md)
   and only use a WAF that the team owns and is authorized to test.

## Query validation boundary

The documented table and column names are based on Microsoft Learn references
listed in the guides. KQL files are not certified against a live workspace:
there is no accessible workspace in the current Azure context. Confirm the
workspace table schema and run each query in Logs before creating an analytics
rule. The WAF rate-limit query additionally requires Person 1 to confirm the
actual custom rule ID/name that represents rate limiting.
