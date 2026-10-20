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
