# Runbook, cost, cleanup, and troubleshooting

## Potential resources and charges

No resource is deployed by this module. Potential charges if the owners later
approve setup include:

| Resource / feature | Potential cost driver |
| --- | --- |
| Log Analytics workspace | Ingested GB by table/plan, retention beyond included period, archive/search operations, and region. |
| Microsoft Sentinel | Analytics/log ingestion and selected commitment/tier; rates and free allowances vary by data source, plan, and region. |
| WAF resource diagnostics | Log volume sent to the workspace; busy access/firewall logs can be high volume. Route only approved categories and monitor ingestion. |
| Entra sign-in logs | Workspace ingestion volume and tenant/license/connector conditions. |
| Defender for Cloud | Selected paid plan, protected resource count, and possible trial ending; free foundational CSPM is distinct from paid workload protection. |
| Logic Apps | Trigger/action executions, connector plan, and any related integration services. |

Check current prices, region, currency, eligibility, and free offers using the
official links below and the subscription's cost-management view before
enabling anything. Prices are not quoted here because region, table plan,
retention, data volume, and workload count are unknown.

- [Microsoft Sentinel pricing](https://azure.microsoft.com/pricing/details/microsoft-sentinel/)
- [Azure Monitor / Log Analytics pricing](https://azure.microsoft.com/pricing/details/monitor/)
- [Defender for Cloud pricing](https://azure.microsoft.com/pricing/details/defender-for-cloud/)
- [Azure Pricing Calculator](https://azure.microsoft.com/pricing/calculator/)
- [Sentinel onboarding prerequisites and pricing](https://learn.microsoft.com/azure/sentinel/quickstart-onboard)
- [Log Analytics cost management](https://learn.microsoft.com/azure/azure-monitor/logs/cost-logs)

At review time, Azure Monitor's official pricing page described regional
ingestion plans (Analytics, Basic, and Auxiliary). The Sentinel pricing URL
redirected to a page that did not expose a regional per-GB estimate in this
review. Use the calculator and the subscription's pricing view for an actual
estimate rather than copying a stale figure into this guide.

Require human approval before workspace creation, enabling Sentinel,
diagnostic settings, ingestion, changing retention, or a Defender trial/plan.
Use cost alerts/budgets and verify they are active; budgets alert but do not
necessarily stop charges.

## Cleanup after an approved demonstration

1. Disable/delete project analytics rules and automation rules/playbook
   connections that are no longer needed.
2. Remove only the diagnostic setting created for this test; do not disable
   settings owned by another team.
3. Turn off any explicitly enabled paid Defender plan only after confirming
   the subscription owner approves and the protected resource is out of scope.
   Check any trial conversion and remaining charges.
4. Delete a temporary workspace only after confirming it contains no
   production/team data, other rules, or required evidence. Follow the
   subscription owner's retention and incident-evidence policy.
5. Remove temporary role assignments and guest/delegated access. Review
   Logic Apps run history for sensitive data and apply the owner's retention
   policy.
6. Verify Cost Management after cleanup; charges can lag resource deletion.

Do not delete shared resources or run cleanup on a workspace that this module
did not create.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| `AGWFirewallLogs` not found | Confirm the actual WAF product, diagnostic category, selected workspace, resource-specific mode, permissions, and ingestion delay. `AzureDiagnostics` mode requires a different query. |
| Query returns no WAF rows | Confirm Person 1 enabled firewall logging and generated an authorized test request. A WAF in detection mode may log without blocking. |
| Rate-limit query returns none | Replace the placeholder with the confirmed `RuleId`, verify the rate-limit feature/configuration and action values, and inspect raw rows before changing threshold. |
| `SigninLogs` not found | The Entra sign-in connector is not configured or is not writing to this workspace. Do not claim failed-sign-in detection until it is. |
| `SecurityAlert` has no Defender rows | Confirm the current Defender integration and source alert, then inspect actual ProviderName/ProductName. No finding may exist. |
| Rule creates too many alerts | Inspect duplicate rule matches, shared NAT/scanners, schedule/lookback overlap, incident grouping, suppression, and source volume. Tune only against observed data. |
| Incident exists but playbook does not run | Check automation rule scope/conditions, workflow enablement, trigger type, managed identity roles, connector connection, and run history. Compare exact trigger payload with mappings. |
| Cross-tenant write fails | Confirm diagnostic destination restrictions and tenant authorization with both Azure owners; do not exchange service credentials as a workaround. |

## Screenshot checklist for the report

- [ ] Workspace and region overview (redact subscription/workspace identifiers).
- [ ] Sentinel enabled on the approved workspace.
- [ ] Connector status and diagnostic category/table-mode settings.
- [ ] Logs query showing a real, authorized WAF record with IP/request data
      redacted as required.
- [ ] Analytics rule query, schedule, severity, incident creation, and entity
      mapping.
- [ ] Real test alert and incident detail/timeline/entities.
- [ ] Logic App trigger run history with the native payload sanitized.
- [ ] Defender plan status and actual recommendation/alert, if one exists.
- [ ] Cost/budget view and cleanup evidence.

Never present inline KQL test output or sample JSON as a screenshot of a live
Azure alert or incident.
