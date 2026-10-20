# Defender for Cloud scope and Sentinel integration

## Recommended minimal scope

Start with the free foundational Cloud Security Posture Management (CSPM)
capabilities to review inventory, recommendations, and Secure Score. These do
not guarantee that a workload protection alert will be generated.

Do not enable all Defender plans to populate a dashboard. Select a paid
workload plan only when the project actually has an in-scope supported resource
and the subscription owner explicitly approves its potential charges. For
this project, use the free posture view for relevant project resources and
consider a workload plan only after inventory confirms its applicable target
(for example, a specific server plan for an owned server). The WAF detection
queries themselves rely on WAF diagnostic logs and do not require a paid
Defender plan.

Defender for Cloud's pricing page currently describes a 30-day free trial for
enhanced capabilities and says usage after the trial is charged. Trial
availability and eligibility can change. Confirm terms in the subscription and
pricing page before enabling anything; do not assume a trial will be free for
all in-scope resources or will not convert to paid usage.

## Findings, permissions, and Sentinel

### Read-only subscription snapshot (2026-10-20)

The `az security pricing list` response reported `Free` pricing tiers for the
listed workload plans (including VirtualMachines, SqlServers, AppServices,
StorageAccounts, and Containers), and `Standard` for `Discovery` and
`FoundationalCspm`; `CloudPosture` reported `Free`. These are recorded as the
API returned them, not interpreted here as an independent billing quote.
No plan was changed during the check. Confirm their current meaning and
subscription charges in Defender for Cloud before any change.

`SecurityAlert` exists as an Analytics table in the workspace, but a
read-only query returned zero rows for the last 30 days. This verifies no
Defender alerts were ingested into this workspace during that period; it does
not prove that the subscription has no recommendations or alerts in the
Defender portal.

The subscription-wide read-only Defender assessment list returned 16 posture
assessments, 7 with `Unhealthy` status. One example was
`Subscriptions should have a contact email address for security issues`.
The Defender security alert list returned zero alerts. A report/demo may show
this existing recommendation as a genuine posture finding, but it is not an
incident or threat alert and does not prove Sentinel alert generation. Do not
enable a plan or remediate a recommendation merely to produce a screenshot.

1. In Defender for Cloud, check the subscription's current CSPM and workload
   plan status and the inventory of actual in-scope project resources.
2. Review the Recommendations and Security alerts pages. A recommendation is
   not necessarily an alert; document the finding type and source accurately.
3. If approved, enable only the relevant plan and review its required resource
   provider registration, permissions, agentless/agent requirements, and
   billing scope shown in the current portal.
4. In Sentinel, use the currently available Defender for Cloud integration
   from Data connectors or Content hub. Microsoft documents a subscription
   connector (legacy) and a tenant-based connector (preview). The current
   connector guide requires read/write workspace permissions, Contributor or
   Owner on the connected subscription, at least one Defender plan enabled
   per connected subscription, and the `SecurityInsights` provider registered.
   Bidirectional alert sync needs additional Contributor or Security Admin
   permissions. This module does not assume a connector is already configured.
5. Verify a real source alert arrives in `SecurityAlert`. Record the actual
   `ProviderName`, `ProductName`, severity, alert ID, and resource ID in
   redacted private evidence. The sample query
   [`defender-cloud-alerts.kql`](../queries/defender-cloud-alerts.kql) is a
   starting point; its product/provider string filter must be checked against
   the workspace's actual records.

Required role assignments depend on the chosen plan and connector action.
Have the subscription owner or security administrator perform setup and grant
the documented least-privilege roles; do not grant Owner to the Logic App or
student accounts by default.

The Defender for Cloud connector does not support syncing alerts from
subscriptions owned by other tenants, even when Azure Lighthouse is enabled.
Do not assume a cross-tenant Sentinel/Defender integration based on shared
college affiliation or delegated access.

## Fallback when no finding exists

If there are no genuine findings, retain the empty/clean posture result as the
real finding and use the clearly labeled record in
[`normalized-alerts.json`](../samples/normalized-alerts.json) for contract
testing only. The sample has `simulation: true`, no resource ARM ID, and no
Sentinel identifiers. It is not an imported Defender event and cannot prove
Defender-to-Sentinel connectivity.

References: [Defender for Cloud pricing](https://azure.microsoft.com/pricing/details/defender-for-cloud/),
[Sentinel connector prerequisites](https://learn.microsoft.com/azure/sentinel/connect-defender-for-cloud),
[SecurityAlert table schema](https://learn.microsoft.com/azure/azure-monitor/reference/tables/securityalert).
