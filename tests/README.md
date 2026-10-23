# ATDR tests

## `waf_tests.py`: WAF tests T1–T6 (any laptop, no setup)

Uses only the Python standard library (Python 3.8 or newer), so nothing needs to be installed.
Run it **only against our own gateway**. The URL is on the portal page
**rg-atdr → atdr-pip-appgw → Overview → IP address**, or ask Anthony.

1. Download `tests/waf_tests.py` from the repository (GitHub → file → *Download raw file*).
2. Open a terminal in the folder where you saved it and run:

   **Windows (PowerShell or Command Prompt)**

   ```powershell
   python waf_tests.py http://<gateway-ip>/
   ```

   **macOS / Linux**

   ```sh
   python3 waf_tests.py http://<gateway-ip>/
   ```

It takes about 1.5 minutes, because T6 waits for the rate-limit window to pass. It sends
roughly 40 requests. Each step prints a `PASS`/`FAIL` line with a UTC timestamp, and the
same output is saved to `waf_test_results_<time>.txt` in the current folder (or choose a
name with `--out myrun.txt`). The exit code is 0 only if every test passed.

| Test | What it sends | Expected |
|---|---|---|
| T1 | `GET /` | 200 |
| T2 | `GET /health` | 200 |
| T3 | `/products?search=' OR 1=1--` (standard SQL-injection test string) | 403 (managed rules) |
| T4 | `/products?search=<script>alert('xss')</script>` (standard XSS test string) | 403 (managed rules) |
| T5 | 30 normal searches as fast as possible | first ones 200, later ones 403 (RateLimitDemo, 20 per minute per IP). The 403s may alternate with 200s, because the gateway has two instances that count separately; that still passes. |
| T6 | wait ~70 s, then `GET /` | 200 (site still healthy) |

Your own IP is rate-limited for the rest of that minute after T5, which is expected.
Run it **once**, not in a loop.

## `test_app.py`: Flask unit tests (developer machine)

```sh
pip install -r webapp/requirements.txt
python -m pytest tests/test_app.py -v
```
