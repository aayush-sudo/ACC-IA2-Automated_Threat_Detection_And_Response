# Delivery checklist and validation evidence

## Implementation checklist

- [x] Inspect repository, branches, Git status, existing files, and README candidates.
- [x] Preserve the pre-existing deleted `SourceControl_Test.txt` worktree change.
- [x] Create and use `feature/sentinel-detection`.
- [x] Define normalized alert schema and four severity examples, labeled simulated.
- [x] Add WAF repeated-block, WAF rate-limit, conditional Entra sign-in, and Defender alert KQL.
- [x] Add inline KQL fixture and synthetic WAF JSON rows.
- [x] Run local standard-library artifact tests and parse all JSON deliverables.
- [x] Document workspace setup, connectors, analytics rules, incidents, permissions, cost, and cleanup.
- [x] Document Defender scope, findings, integration, and no-finding fallback.
- [x] Document Person 1 / Person 3 handoffs and trigger-schema boundaries.
- [x] Add troubleshooting, screenshot evidence checklist, and demo script.
- [ ] Execute KQL against an authorized live workspace and validate results.
- [ ] Generate and verify a real Sentinel alert and incident.
- [ ] Validate actual WAF logs and rate-limit identifier with Person 1.
- [ ] Validate native incident trigger mapping and dry-run with Person 3.
- [ ] Confirm project owner approval, costs, regional availability, and cleanup.

## Evidence boundary

- Microsoft Learn was consulted for the `AGWFirewallLogs`, `SigninLogs`, and
  `SecurityAlert` tables and Sentinel onboarding requirements.
- Azure workspace discovery in the active/default context returned an empty
  workspace list. This is not a search of all possible tenants/subscriptions.
- No Azure resources, Defender plans, connectors, diagnostic settings, rules,
  alerts, incidents, or Logic Apps were created or changed.
- Sample payloads and event records are synthetic. They use reserved
  documentation IP addresses and have `simulation: true` where normalized.
- Four local standard-library artifact tests passed; all three JSON files
  parsed successfully. A passing local artifact test does not validate KQL
  execution or Azure integration.
