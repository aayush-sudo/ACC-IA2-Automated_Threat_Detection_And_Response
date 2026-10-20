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
   Logs experience. In the active subscription context used for this module,
   workspace discovery returned no workspace.

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
this project's query execution is pending a real workspace.

### Entra sign-in logs

Only configure this connector if the team has an authorized Entra tenant and
needs the signals. In Sentinel **Content hub**, install or update the Microsoft
Entra ID solution, then open its data connector and follow its current
instructions to connect sign-in logs. Verify `SigninLogs` exists and check
`ResultType`, `IPAddress`, and `UserPrincipalName` before enabling
[`entra-repeated-failed-signins.kql`](../queries/entra-repeated-failed-signins.kql).
Entra licensing, permissions, and availability vary; do not assume this data
source is already configured.

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

## Build analytics rules (portal-first)

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
