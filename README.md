# Automated Threat Detection and Response

This repository currently contains the Sentinel monitoring module under
[`sentinel-rules/`](./sentinel-rules/). It provides KQL detections, sample data,
an alert contract, onboarding guidance, and local artifact tests.

No Azure resources were created or changed by this repository. Read-only
verification on 2026-10-20 confirmed the project Log Analytics workspace and
Microsoft Sentinel onboarding resource. The target tables had no source rows
in the checked 30-day period; no live Sentinel alert or incident was generated.
The included sample events and alert payloads are simulations.

Start with [`sentinel-rules/README.md`](./sentinel-rules/README.md) for status,
prerequisites, and the demonstration path. See
[`sentinel-rules/docs/checklist.md`](./sentinel-rules/docs/checklist.md) for the
delivery checklist and
[`sentinel-rules/docs/integration.md`](./sentinel-rules/docs/integration.md)
for Person 1 and Person 3 handoffs.

## Live deployment (Anthony)

The paragraphs above describe the Sentinel module as it was written in Person
2's own workspace. This section describes the separate, **live end-to-end
prototype**, built in Anthony's Azure for Students subscription (resource group
`rg-atdr`, Central India) and reusing Person 2's KQL and alert contract.

**Chain.** Internet → Application Gateway WAF_v2 (`atdr-appgw`, policy
`atdr-wafpolicy`) → Flask demo shop on a private VM (`atdr-vm-backend`). WAF
logs go to `atdr-law`, where two Sentinel analytics rules create incidents. An
automation rule runs the Logic App `atdr-playbook-contain`, which snapshots,
isolates and tags the VM, comments on the incident, and notifies Discord.

**Verified live, 22–24 Oct 2026** (details in [`docs/test-results.md`](./docs/test-results.md)):
- Two full automated runs: about 30 s from incident to verified isolation, and
  the playbook was started by the automation rule.
- A timed manual baseline of the same steps: 17 min.
- Four real internet-scanner incidents.
- Rollback back to HTTP 200 and Healthy.

| Folder | Contents |
|---|---|
| [`webapp/`](./webapp/) | Flask demo app and its systemd unit |
| [`infra/`](./infra/) | foundation, web-app deployment, WAF policy, gateway create/delete, `cleanup.sh`, `kql.sh` |
| [`detection-live/`](./detection-live/) | live versions of Person 2's WAF queries, rule deployment, automation-rule switch |
| [`response/`](./response/) | playbook ARM template, deployment, test and rollback scripts |
| [`tests/`](./tests/) | Flask unit tests, `waf_tests.py` (any laptop), `e2e_run.sh` (end-to-end and manual baseline) |
| [`evidence/`](./evidence/) | numbered, timestamped verification output (IDs and IPs masked) |
| [`docs/`](./docs/) | [how it works](./docs/how-it-works.md), [architecture](./docs/architecture.md), [test results](./docs/test-results.md), [demo script](./docs/demo-script.md), [screenshots](./docs/screenshots-checklist.md), [cost and cleanup](./docs/cost-and-cleanup.md) |

`sentinel-rules/` is unchanged. The live queries in `detection-live/` name
their source file in Person 2's module and document every change.

**Cost.** The gateway is about US$0.50/h, and everything else costs cents. After
recording, run `bash infra/cleanup.sh`. Deleting the whole resource group is a
separate, confirmed step; see [`docs/cost-and-cleanup.md`](./docs/cost-and-cleanup.md).
