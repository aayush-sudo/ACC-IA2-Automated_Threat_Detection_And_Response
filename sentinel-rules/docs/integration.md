# Integration handoff: WAF owner and Logic Apps owner

## Person 1 — WAF resource and diagnostics

Please provide these facts through an authorized team channel before treating
the WAF queries as production-ready:

1. WAF product/SKU and resource type (for example, Application Gateway WAF or
   Front Door WAF), deployment tenant/subscription, region, resource group,
   and real resource ARM ID.
2. Actual diagnostic destination and workspace resource ID, whether the
   resource is in the same tenant as the workspace, and the selected table
   mode (resource-specific or `AzureDiagnostics`).
3. Selected diagnostic categories, especially the firewall log category, and
   a redacted sample record showing the actual table, columns, `Action`,
   `RuleId`/rule name, timestamp, client IP, and transaction/reference ID.
4. For rate limiting, the exact configured rule identifier/name, action and
   window. Verify that this WAF SKU and rule configuration supports the
   intended rate-limit behavior.
5. An authorized safe test path and approval window; do not share credentials,
   keys, tokens, or unredacted request bodies.

The current queries target the documented resource-specific
`AGWFirewallLogs` table. They will not see events until Person 1 configures
diagnostic settings to send logs to the chosen workspace. If the WAF is Front
Door, older Azure Diagnostics mode, or another resource, confirm its actual
table schema and adapt the query before enabling a rule.

### Tenant boundary

GitHub collaboration and a shared college affiliation grant no Azure access.
Both owners must confirm the tenant/workspace and receive explicit
organization authorization. Use B2B guest access or Azure Lighthouse only if
the resource owners approve it and the required operation is supported by
that arrangement. Cross-tenant diagnostic destinations may be restricted;
validate the actual supported path before assuming a resource can write to a
workspace in another tenant. A safe alternative is for Person 1's authorized
tenant to provide a minimal, redacted event export through a security-approved
handoff or approved integration endpoint. Do not exchange credentials or
copy raw logs into Git.

## Person 3 — response playbook contract

### Normalized output

Person 3 should consume
[`normalized-alert.schema.json`](../alert-contract/normalized-alert.schema.json)
and treat the schema as the project-owned contract. Required keys:

| Field | Meaning |
| --- | --- |
| `alert_id` | Normalizer/workflow stable ID; not necessarily a Sentinel ID. |
| `severity` | `low`, `medium`, `high`, or `critical`. |
| `source` | Origin such as `application_gateway_waf`, `entra_id`, or `defender_for_cloud`. |
| `timestamp` | UTC RFC 3339 event time. |
| `recommended_action` | Human-reviewed next step; not an instruction to autonomously block a source. |

`resource_id` must be a real ARM ID from a real event or `null`. Optional
`sentinel` fields hold actual incident/alert identifiers only after they are
available. Optional `evidence` is data-minimized. Never take a sample ID,
sample IP, or null resource ID as an operational target.

### Trigger selection and mapping

For incident-aware response, choose the Microsoft Sentinel incident trigger
in the Microsoft Sentinel Logic Apps connector (the incident trigger's exact
label can vary with the designer). Configure an automation rule to invoke the
approved playbook when an incident is created or updated, with filtering to
prevent loops. The trigger's native JSON is not this normalized contract:
connector versions and payload envelopes can differ.

Map from the actual trigger's dynamic content / trigger schema into the
normalized contract after running a real, approved test incident. Typical
sources to inspect include the incident's system identifier, incident number,
severity, title, URL, alert list, entities, and workspace/resource context.
Use the native run history as the source of truth; do not hard-code paths
based on the simulated samples. Map source-specific fields from the Sentinel
alert evidence, not from the incident title.

The examples in `samples/normalized-alerts.json` are normalized examples,
not Sentinel trigger payloads. No native trigger payload has been collected:
no project Logic App playbook or real incident run history was available for
this check.

### Suggested field mapping

Use the native incident trigger dynamic content for incident values. When
normalizing an alert record, the documented `SecurityAlert` table can provide
the following starting points; verify which values the chosen trigger actually
includes:

| Normalized field | Candidate source / mapping |
| --- | --- |
| `alert_id` | Normalizer-generated stable ID; use the native alert ID as a source key if present. |
| `severity` | Normalize the actual alert/incident severity to lowercase contract values. Keep the original in `evidence.native_severity`; do not invent `critical` when the source does not report it. Agree on any mapping for informational/unknown values with Person 3. |
| `source` | `SecurityAlert.ProductName` or `ProviderName`, normalized to agreed source labels such as `defender_for_cloud`; WAF/sign-in rules can use a fixed detector source. |
| `resource_id` | `SecurityAlert.ResourceId` or an actual resource ARM ID from incident context; otherwise `null`. |
| `timestamp` | Prefer source event time (`StartTime` when available); use `TimeGenerated` only when that is the timestamp exposed. Keep event time UTC. |
| `recommended_action` | Approved `RemediationSteps` when appropriate; otherwise a reviewed action mapped from the detection rule. Never auto-execute a remediation string. |
| `sentinel.system_alert_id` | `SecurityAlert.SystemAlertId` or the connector's native alert identifier. |
| `sentinel.incident_arm_id`, `incident_number`, `incident_url` | Map from actual incident trigger dynamic fields/run history; exact native JSON paths are connector-version-specific. |
| `evidence.alert_name`, `provider`, `native_severity` | Map from `AlertName`, `ProviderName`/`ProductName`, and the source severity respectively. |
| `evidence` entity fields | Extract only allowlisted IP, account, URI, or rule identifiers from `Entities`/custom details. Do not copy the complete raw alert/entity payload by default. |

If a field is absent, use the schema's optional behavior or `null` only where
the schema permits it. Preserve the source identifiers in the normalizer's
private idempotency store if `alert_id` is generated independently.

### Roles and safe invocation

- Give the Logic App system-assigned managed identity only the roles needed
  for the chosen actions and workspace. For incident updates, use the
  Microsoft Sentinel role documented by the connector (commonly Microsoft
  Sentinel Responder) at the narrowest supported scope. Querying workspace
  data may separately require a Logs reader role. Verify current connector
  documentation and test each action; avoid subscription-wide Owner or
  Contributor.
- Prefer managed identity and a managed connector connection. Do not commit
  connection strings, webhook URLs, or secrets to Git.
- First test with a simulation flag / dry-run branch that only logs a sanitized
  normalized object and performs no containment, account change, or network
  block. Compare each output against the JSON Schema.
- Then, with both owners' approval, use a real low-impact test event on the
  owned test application, verify incident creation and mapping, and keep any
  response action human-approved until the project owners explicitly authorize
  automation.

### Handoff checklist

- [ ] Person 1 confirms actual WAF/table/fields/rate-limit rule and the safe test.
- [ ] Workspace and cross-tenant access path are approved by both tenant owners.
- [ ] Person 3 confirms trigger and mapping using a real test run-history export.
- [ ] Owners agree on severity mapping and safe/no-action behavior.
- [ ] No secrets or real identifiers are added to the repository.
