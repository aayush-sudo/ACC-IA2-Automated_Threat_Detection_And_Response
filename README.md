# Automated Threat Detection and Response

This is our Advanced Cloud Computing project on using Microsoft Sentinel to
identify suspicious activity in Azure. We wrote Kusto Query Language (KQL)
queries for common security events and prepared sample data and an alert
format to show how detections could connect to a response workflow.

The project files are in [`sentinel-rules/`](./sentinel-rules/). They include
queries, sample records, tests, and instructions for setting up and reviewing
the project. The repository does not deploy Azure resources or automatically
take action on accounts or other resources.

## What the project checks

The queries cover these scenarios:

- Repeated blocked web application firewall (WAF) requests and WAF rate-limit
  events from `AGWFirewallLogs`.
- Repeated failed Entra ID sign-ins from `SigninLogs`.
- Defender for Cloud findings from `SecurityAlert`.
- Repeated failed Azure administrative operations from `AzureActivity`.

We also added standalone queries with inline sample records for Azure
Activity, WAF, and Entra ID. These let us see the expected query results
without relying on incoming source logs.

The alert JSON Schema describes the information expected by a future
response workflow, such as severity, source, timestamp, recommended action,
and optional resource and Sentinel identifiers. The included examples cover
four severity levels. The schema describes the data format.

## Project files

- [`sentinel-rules/queries/`](./sentinel-rules/queries/) — detection queries
  and queries with inline sample data.
- [`sentinel-rules/tests/`](./sentinel-rules/tests/) — query fixtures and
  local checks for project files.
- [`sentinel-rules/alert-contract/`](./sentinel-rules/alert-contract/) —
  normalized alert JSON Schema.
- [`sentinel-rules/samples/`](./sentinel-rules/samples/) — sample alerts,
  response output, and WAF events.
- [`sentinel-rules/docs/`](./sentinel-rules/docs/) — setup, integration,
  walkthrough, cost, and project status information.
