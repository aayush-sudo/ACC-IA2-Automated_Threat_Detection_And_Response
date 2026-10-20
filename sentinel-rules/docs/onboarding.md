# Sentinel onboarding and analytics rules

## Before starting

- Obtain explicit approval from the subscription/workspace owner for any
  resource creation, connector, diagnostic setting, data ingestion, or paid
  feature. No deployment is performed by these instructions.
- Confirm the Azure tenant, subscription, region, workspace owner, data
  residency requirements, billing owner, retention, and approved test scope.
- Microsoft Sentinel is a paid service. Review the current service pricing,
  Log Analytics ingestion/retention pricing, and Defender pricing links in
  [`runbook-and-cost.md`](./runbook-and-cost.md). A price cannot be estimated
  responsibly without region, ingestion volume, retention, and plan choices.
- Ensure the workspace region and service availability meet current
  requirements; verify the selected region in the portal at setup time.

## Workspace and Sentinel

1. In the Azure portal, select **Log Analytics workspaces** and create or select
   a workspace in the approved subscription and region. Record its workspace
   resource ID and tenant, but do not commit identifiers or sensitive data to
   this repository.
2. Review workspace retention and pricing. Microsoft Sentinel onboarding docs
   note a 90-day retention requirement for full Sentinel functionality; check
   current feature requirements and billing before changing retention.
3. Open **Microsoft Sentinel**, choose **Create** or **Add**, and select the
   approved workspace. Confirm the portal's current Sentinel experience and
   regional availability.
4. Assign only necessary roles. Microsoft documents subscription Contributor
   for enabling Sentinel, and Microsoft Sentinel Contributor or Reader at the
   workspace resource group for Sentinel use. Use a narrower role/scope when
   the current operation supports it; do not grant Owner by default.
5. Confirm the workspace is visible in Sentinel and that the team can open the
   Logs experience. The project workspace and Sentinel onboarding resource
   were verified read-only on 2026-10-20. The owner reports that the trial
   expires on 2026-11-20; this date was not independently verified by CLI.
6. `SigninLogs`, `SecurityAlert`, `AGWFirewallLogs`, and `AzureActivity` table
   definitions exist. Read-only 30-day queries returned zero rows for each;
   do not treat table existence as proof of a configured source connector.
7. The Defender assessment API returned posture recommendations, including
   unhealthy statuses; the Defender alert API returned zero security alerts.
   Review these separately from Sentinel incidents.

### Azure Activity Log export status

The `AzureActivity` table exists and its schema was checked in the workspace,
but it has no rows. The subscription initially had no Activity Log diagnostic
setting. The existing built-in policy assignment named **Configure Azure
Activity logs to stream to specified Log Analytics workspace** was found at
resource-group scope even though its definition targets the subscription
resource. After owner approval, the resource-group assignment was replaced by
a subscription-scope assignment. Its new managed identity has Monitoring
Contributor at subscription scope and Log Analytics Contributor on the
existing workspace.

The owner also approved remediation. Task `remediate-azure-activity-log` is
currently `Evaluating`; the latest read-only check still found no subscription
diagnostic setting and no `AzureActivity` rows. Verify task completion and the
setting before treating the source as configured. The policy routes the
configured subscription-wide Activity Log categories into the workspace and
can incur ongoing ingestion charges; exact volume/cost remains unknown.

Replacing the assignment deleted its old system-assigned identity. Four
resource-group/workspace role-assignment records remain for that deleted
principal. They do not grant access to the new identity, and their removal is
pending explicit approval. Do not remove them until authorized. See
[`azure-activity-repeated-failures.kql`](../queries/azure-activity-repeated-failures.kql)
for a prepared detection, not a live detection.

## Connect sources

### Person 1: WAF logs

WAF resource logs are not collected by default. Person 1 must set a diagnostic
setting on the actual WAF resource and select the firewall log category. Route
to the agreed Log Analytics workspace. Prefer resource-specific destination
tables when the portal offers that mode, then confirm `AGWFirewallLogs` and its
columns in Logs. For older diagnostic mode, the data may instead be in
`AzureDiagnostics`; do not run the resource-specific query unchanged against
that mode.

Use a single authorized event against the team's own application to verify
arrival before enabling repeated-event rules. The `AGWFirewallLogs` table and
column names in the provided queries are verified from Microsoft Learn, but
the query has not been validated against live WAF events. A read-only
30-day check returned no
`AGWFirewallLogs` rows. The resource group inventory showed only the workspace
and Sentinel resources, not an Application Gateway. Person 1's WAF may be in
another resource group/subscription; verify ownership and workspace routing
before using these detections.

### Entra sign-in logs

Only configure this connector if the team has an authorized Entra tenant and
needs the signals. First inspect the connector status in the portal using the
read-only steps below. Do not install/update the Microsoft Entra ID Content
hub solution or connect the source unless the owner explicitly approves it.
After approval, follow the connector's current instructions. Verify
`SigninLogs` exists and check
`ResultType`, `IPAddress`, and `UserPrincipalName` before enabling
[`entra-repeated-failed-signins.kql`](../queries/entra-repeated-failed-signins.kql).
Entra licensing, permissions, and availability vary; do not assume this data
source is already configured.

For the immediate read-only check, open the Sentinel workspace in the Azure
portal, select **Configuration > Data connectors**, and inspect the Microsoft
Entra ID connector's status without selecting **Connect** or installing a
solution. If it is not already connected, stop and request approval before
enabling it. A filtered KQL query does not filter connector ingestion: enabling
the connector may ingest sign-in events for the tenant, not only the test
account, so check the estimated volume/cost first.

The workspace has a `SigninLogs` table, but a read-only 30-day query found no
records. No Sentinel data-connector ARM resources were returned by the
read-only subscription listing. Inspect the current connector status in the
portal before assuming the source is connected.

### Defender for Cloud

Use the currently supported Defender for Cloud/Sentinel integration flow from
the Sentinel Data connectors or Content hub experience. Product names and
connector UI may change; follow the in-portal connector's current
prerequisites. Confirm a known source alert appears in `SecurityAlert` and
inspect the actual `ProviderName` and `ProductName` before relying on the
example product-name filter. Details are in [`defender-for-cloud.md`](./defender-for-cloud.md).

The current Microsoft Learn connector guide documents a subscription-based
legacy connector and a tenant-based connector in preview. It requires
read/write permissions on the Sentinel workspace, Contributor or Owner on
each connected subscription, at least one Defender plan enabled per connected
subscription, and the `SecurityInsights` resource provider registered.
Bidirectional sync has additional Contributor or Security Admin requirements.
Confirm current portal experience and permissions; do not enable a paid plan
solely to satisfy a connector prerequisite without owner approval.

## Conditional low-volume demo rule: one failed sign-in

The most contained candidate using a table already provisioned is
[`entra-single-failure-demo.kql`](../queries/entra-single-failure-demo.kql).
It filters to one dedicated approved test-account UPN and detects a single
failure in a 15-minute window. However, the current workspace has no
`SigninLogs` rows; this rule cannot fire until the owner approves connecting
Entra sign-in logs and data arrives. Do not perform a failed sign-in or enable
the connector as part of this guide without that approval.

After data-source approval and a successful Logs test, use:

- Rule type: Scheduled query rule.
- Name: `Demo - Single failed Entra sign-in for test account`.
- Query: `queries/entra-single-failure-demo.kql`, replacing the UPN with an
  approved dedicated test account.
- Query frequency: 5 minutes; lookup period: 15 minutes; alert threshold:
  greater than 0; alert suppression: 1 hour for the one-off demo.
- Severity: Low; incident creation: enabled for the isolated test.
- Entity mappings: `UserPrincipalName` to Account/UPN and `IPAddress` to IP.
- Trigger a single deliberate failed sign-in only for the dedicated test
  account after owner approval; do not repeat attempts or use an account that
  could be locked out. Verify query row first, then alert, then incident as
  separate outcomes.

This configuration is prepared, not deployed or validated against a real
sign-in event.

## Build other analytics rules (portal-first)

Create a separate **Scheduled query rule** for each live query. The exact
wizard labels can change; confirm them in the current portal.

1. In Sentinel, open **Analytics** and start creating a scheduled query rule.
2. Paste one query from `queries/` and run it in Logs first. Resolve schema or
   table errors and ensure the returned columns include the intended entities.
3. Suggested initial settings:
   - WAF repeated blocks: query frequency 5 minutes, lookup period 15 minutes,
     alert threshold greater than 0; query threshold is 5 distinct transactions.
   - WAF rate limit: query frequency 5 minutes, lookup period 10 minutes,
     alert threshold greater than 0; set the real rule ID before enabling.
   - Failed sign-ins: query frequency 5 minutes, lookup period 15 minutes,
     alert threshold greater than 0; only after Entra logs are connected.
   - Azure Activity repeated failures: query frequency 5 minutes, lookup
     period 15 minutes, alert threshold greater than 0; only after approved
     subscription Activity Log export is configured and rows arrive. Start
     at **Medium** severity, with `CallerIpAddress` mapped to IP address and
     `Caller` retained as custom evidence (its value can be a principal ID).
   - Defender alerts: query frequency 15 minutes, lookup period 24 hours.
     This can re-alert on existing rows; prefer the native connector alert
     workflow or add a tested suppression/incident grouping strategy.
4. Set rule severity and tactics deliberately. Suggested starting severities:
   WAF repeated blocks **Medium**, WAF rate limit **Low** (tune to the rule and
   asset), repeated failed sign-ins **High**, Defender severity **inherit or
   map from the source**. Do not set a Critical production rule based on the
   synthetic examples.
5. Enable incident creation for detections that need a response. Configure
   entity mappings from `ClientIp` / `IPAddress` to IP address and include
   `ResourceId` only when it is a real ARM ID. Map the alert query fields as
   custom details only if they contain approved, minimized evidence.
6. Save the rule, note its name, schedule, suppression/grouping settings, and
   rule identifier in the team's deployment evidence. Export the rule from
   the portal when the current experience supports export, or record the
   portal-only configuration. Do not represent a query file as a deployed
   analytics rule.

For Azure Activity, use
[`azure-activity-repeated-failures.kql`](../queries/azure-activity-repeated-failures.kql).
It groups failed Administrative operations by caller and caller IP over 15
minutes and returns groups with at least five failures. Run it in Logs after
the approved export is active; a query row is not itself a Sentinel alert or
incident. Its synthetic fixture is
[`azure-activity-repeated-failures-test.kql`](../tests/azure-activity-repeated-failures-test.kql)
and does not generate an alert or incident.

## Verify an alert and incident

1. First prove data arrival with a narrow query such as
   `AGWFirewallLogs | where TimeGenerated > ago(1h) | take 10`.
2. Use a safe request to the team's own test endpoint that causes the agreed
   WAF rule to log or block it. Do not attack an external system, production
   endpoint, or another person's resource.
3. Wait for the documented ingestion latency, run the detection query, and
   confirm its grouping keys and threshold. Record timestamps, rule ID, event
   count, and a redacted result.
4. Confirm the analytics rule generated an alert. If incident creation is
   enabled, verify the incident in Sentinel, open its entities, alerts,
   timeline, activity log, and investigation graph where available.
5. Export a real, redacted trigger run from Logic Apps only after the
   integration owner approves it. Do not substitute the sample alert payload.

The KQL files in `tests/` are inline query-shape fixtures only; running them
does not test a workspace connector, create an alert, or create an incident.

## API, region, and export boundary

This module is intentionally portal-first: it contains no ARM/Bicep/API
deployment definition, so there is no API version to validate or deploy.
Microsoft Sentinel onboarding requires a Log Analytics workspace, supported
pricing tier, and no resource lock; check current prerequisites before setup.
Choose a region from the current Azure Monitor availability list and verify
Sentinel availability in the portal. The portal is the source of truth for
available connectors, current role requirements, and whether a particular
rule can be exported. Capture portal-only settings when export is unavailable.

References checked for this guide:

- [Onboard to Microsoft Sentinel](https://learn.microsoft.com/azure/sentinel/quickstart-onboard)
- [Microsoft Sentinel deployment prerequisites](https://learn.microsoft.com/azure/sentinel/prerequisites)
- [Ingest Defender for Cloud alerts into Sentinel](https://learn.microsoft.com/azure/sentinel/connect-defender-for-cloud)
- [Azure resource logs and diagnostic settings](https://learn.microsoft.com/azure/azure-monitor/logs/resource-logs)
- [Azure Monitor regional availability](https://azure.microsoft.com/regions/services/)
- [AGWFirewallLogs table schema](https://learn.microsoft.com/azure/azure-monitor/reference/tables/agwfirewalllogs)
- [SigninLogs table schema](https://learn.microsoft.com/azure/azure-monitor/reference/tables/signinlogs)
- [SecurityAlert table schema](https://learn.microsoft.com/azure/azure-monitor/reference/tables/securityalert)
- [AzureActivity table schema](https://learn.microsoft.com/azure/azure-monitor/reference/tables/azureactivity)
- [Create diagnostic settings with built-in Azure Policy](https://learn.microsoft.com/azure/azure-monitor/data-collection/diagnostic-settings-policy-built-in)
- [Remediate Azure Policy resources](https://learn.microsoft.com/azure/governance/policy/how-to/remediate-resources)

## Access and evidence

- Sentinel onboarding documentation: active Azure subscription; Contributor
  permissions are documented for enabling Sentinel; Microsoft Sentinel
  Contributor or Reader at the workspace resource group for Sentinel use.
- Workspace and resource diagnostic settings: use roles that allow only the
  approved workspace/resource configuration, scoped as narrowly as possible.
- Record tenant, subscription, workspace resource ID, connector status, table
  mode, diagnostic categories, and role scopes in a private team handoff, not
  Git. Never add keys, tokens, raw incident data, or account secrets here.
- See [`integration.md`](./integration.md) for cross-tenant and Logic Apps
  requirements and [`runbook-and-cost.md`](./runbook-and-cost.md) for cleanup.
