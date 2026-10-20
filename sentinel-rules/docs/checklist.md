# Delivery checklist and validation evidence

## Implementation checklist

- [x] Inspect repository, branches, Git status, existing files, and README candidates.
- [x] Preserve the pre-existing deleted `SourceControl_Test.txt` worktree change.
- [x] Create and use `feature/sentinel-detection`.
- [x] Define normalized alert schema and four severity examples, labeled simulated.
- [x] Add WAF repeated-block, WAF rate-limit, conditional Entra sign-in, and Defender alert KQL.
- [x] Add inline KQL fixture and synthetic WAF JSON rows.
- [x] Run local standard-library artifact tests and parse all JSON deliverables.
- [x] Verify subscription, workspace, Sentinel onboarding resource, candidate table inventory, and Defender plan tiers with read-only Azure CLI/MCP calls.
- [x] Check `SigninLogs`, `SecurityAlert`, `AGWFirewallLogs`, and `AzureActivity` for rows over the retained 30-day window.
- [x] Execute all six production query files against their actual workspace tables; each parsed successfully and returned zero matching live rows.
- [x] Execute all six inline KQL fixtures in the workspace Logs query API and verify their expected synthetic aggregations.
- [x] Prepare a dedicated-account, single-failure Entra demo query and analytics-rule settings without enabling a connector or rule.
- [x] Inspect the Azure Activity policy assignment, compliance state, remediation tasks, identity role scopes, actual table schema, and subscription diagnostic settings read-only.
- [x] Add a schema-based Azure Activity repeated-failure query and synthetic inline fixture; do not present it as live detection.
- [x] Document workspace setup, connectors, analytics rules, incidents, permissions, cost, and cleanup.
- [x] Document Defender scope, findings, integration, and no-finding fallback.
- [x] Document Person 1 / Person 3 handoffs and trigger-schema boundaries.
- [x] Add troubleshooting, screenshot evidence checklist, and demo script.
- [ ] Execute a detection query against nonempty real source data and validate results.
- [ ] Generate and verify a real Sentinel alert and incident.
- [ ] Validate actual WAF logs and rate-limit identifier with Person 1.
- [ ] Validate native incident trigger mapping and dry-run with Person 3.
- [ ] Confirm project owner approval, costs, regional availability, and cleanup.

## Evidence boundary

- Read-only checks on 2026-10-20 confirmed the `Azure for Students`
  subscription, Korea Central workspace, 30-day retention, and Sentinel
  onboarding resource.
- `SigninLogs`, `SecurityAlert`, `AGWFirewallLogs`, and `AzureActivity` tables
  exist, but checks returned no rows in the last 30 days.
- The workspace's actual `AzureActivity` schema was read with `getschema`.
  The query is based on verified columns and is prepared for repeated failed
  Administrative events, but the subscription has no Activity Log diagnostic
  setting and the table is empty.
- The Activity Log policy assignment exists at the resource-group scope,
  whereas its built-in definition targets the subscription resource and
  deploys a subscription-level diagnostic setting. The read-only policy state
  and remediation lists returned no rows. The assignment identity currently
  has Monitoring Contributor and Log Analytics Contributor at the resource
  group/workspace scopes, but no subscription-scope role. No policy,
  diagnostic setting, role assignment, or remediation was changed.
- The Azure Activity query and fixture are schema-tested and labeled
  simulated-only; no query result from real events, alert, or incident exists.
- All six detection query files ran read-only against the actual workspace
  tables and returned zero rows/groups without schema errors. This validates parsing
  and referenced columns only; it does not prove detection behavior against
  real events.
- All six inline KQL fixtures were run in workspace Logs using in-memory
  `datatable` rows; they returned the expected simulated results. The first
  rate-limit fixture run missed its 10-minute boundary due to a timestamp at
  exactly 10 minutes; the fixture was corrected to use events within the
  window and then returned its expected result. These tests did not ingest
  sample data or create alerts/incidents.
- Defender for Cloud returned 16 posture assessments, 7 with `Unhealthy`
  status; the Defender security-alert list returned zero alerts.
  Recommendations are not Sentinel alerts/incidents.
- No analytics-rule resources were found in the project resource group.
- No `Microsoft.SecurityInsights/dataConnectors` resources were returned by
  the subscription-wide ARM resource listing; verify connector status in the
  portal rather than treating this as proof that no source is connected.
- Defender plan API output reported `Free` tiers for workload plans and
  `Standard` for `Discovery` and `FoundationalCspm`; no plan was changed. The
  API tier labels are recorded as returned and are not interpreted as a new
  billing determination here.
- No Azure resources, Defender plans, connectors, diagnostic settings, rules,
  alerts, incidents, or Logic Apps were created or changed.
- Sample payloads and event records are synthetic. They use reserved
  documentation IP addresses and have `simulation: true` where normalized.
- The owner reported a Sentinel trial end date of 2026-11-20; that portal date
  was not independently read from the Sentinel API.
- Four local standard-library artifact test methods cover the single-failure
  fixture and other deliverables; KQL fixture execution is additional and
  synthetic. Neither creates an Azure alert/incident.
