# Sentinel simulation demo

This portal demo executes three self-contained KQL queries that define their
own synthetic rows with `datatable`. They do not read populated source tables,
ingest data, create analytics rules, generate Sentinel alerts/incidents, or
invoke a Logic App. `Simulation = true`, reserved documentation IPs, and
`.invalid` account names mark the examples as non-production.

## Before presenting

- Open the [Azure portal](https://portal.azure.com/) and sign in.
- Open **Microsoft Sentinel** and select the project workspace
  `law-threat-detection-aayush`.
- Select **Logs** from the workspace/Sentinel navigation. If prompted, choose
  the workspace as query scope.
- Keep the three query files from `sentinel-rules/queries/` available locally.
  Open one file, copy its entire contents, paste into the Logs query editor,
  and click **Run**. Repeat one query at a time; each file is standalone.

## Demo sequence

### 1. Repeated failed Azure administrative operations

Open `queries/azure-activity-repeated-failures-demo.kql`, paste the full query,
and click **Run**.

Expected: one result row, `Caller=demo-principal`,
`CallerIpAddress=192.0.2.99`, `FailedOperationCount=5`, and
`Simulation=true`. Four failures for a different principal remain below
threshold; the success is excluded; the sixth failure is outside 15 minutes.

Say: “This query demonstrates a threshold of five failed Administrative
operations from the same caller and IP in 15 minutes. The input is an
in-memory synthetic table; it does not prove our pending Azure Activity export
is delivering real events, and this query result is not a Sentinel alert.”

### 2. Repeated blocked web requests

Open `queries/waf-repeated-blocks-demo.kql`, paste the full query, and click
**Run**.

Expected: one row for `ClientIp=192.0.2.20`, `blockedTransactions=5`, and
`Simulation=true`. A duplicate transaction increases `blockedEvents` but not
the distinct-transaction count; allowed traffic and the old event are
excluded.

Say: “The detection groups by client IP and requires five distinct blocked
transactions in 15 minutes. These are synthetic rows, not WAF diagnostic logs
or a live Sentinel alert.”

### 3. Repeated failed sign-ins

Open `queries/entra-repeated-failed-signins-demo.kql`, paste the full query,
and click **Run**.

Expected: one row for `IPAddress=192.0.2.50`, `failures=10`,
`affectedAccounts=2`, and `Simulation=true`. The successful sign-in, nine
failures from a second IP, and the old failure do not meet the detection.

Say: “This simulates ten failed sign-ins from one IP in 15 minutes. It is
independent of the Entra connector. The production detection still requires
approved Entra sign-in ingestion and real `SigninLogs`.”

## Alert and response contract example

Open `samples/demo-normalized-alert.json` to show a normalized, simulated
medium-severity example. Its `resource_id` and Sentinel alert/incident IDs are
null, and its evidence has `simulation: true`.

Open `samples/demo-simulated-response.json` to show the corresponding
non-executing response illustration. `logic_app_invoked`,
`sentinel_alert_created`, and `sentinel_incident_created` are all false;
`resource_changed` and `account_disabled` are also false. It is not a Logic
App run result.

## Safe demo boundaries

- Do not create an analytics rule or enable a data source just to run this
  simulation.
- Running the query in Logs displays matching rows only. It does not generate
  an alert/incident or invoke an automation playbook.
- A real alert demo requires a configured connector or diagnostic setting,
  a production-table query result, an enabled analytics rule, and separate
  verification of the resulting alert and incident.
- Use only project-owned resources for any separately approved live test.
