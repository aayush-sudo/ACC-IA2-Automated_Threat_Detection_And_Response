# Automated Threat Detection and Response

This repository currently contains the Sentinel monitoring module under
[`sentinel-rules/`](./sentinel-rules/). It provides KQL detections, sample data,
an alert contract, onboarding guidance, and local artifact tests.

No Azure resources are created by this repository. The active Azure context
available during preparation returned no Log Analytics workspaces. Therefore,
the included data and alert examples are simulations; there are no claimed
deployed alerts, incidents, or Azure test results.

Start with [`sentinel-rules/README.md`](./sentinel-rules/README.md) for status,
prerequisites, and the demonstration path. See
[`sentinel-rules/docs/checklist.md`](./sentinel-rules/docs/checklist.md) for the
delivery checklist and
[`sentinel-rules/docs/integration.md`](./sentinel-rules/docs/integration.md)
for Person 1 and Person 3 handoffs.
