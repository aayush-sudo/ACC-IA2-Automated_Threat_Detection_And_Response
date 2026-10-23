#!/usr/bin/env python3
"""ATDR WAF test run (T1-T6) against OUR OWN Application Gateway only.

Standard library only (Python 3.8+), so it runs on any Windows/Mac/Linux laptop:

    python waf_tests.py http://<gateway-public-ip>/          (Windows)
    python3 waf_tests.py http://<gateway-public-ip>/         (macOS / Linux)

Sends about 40 requests in total, using standard, documented WAF test strings:
  T1  GET /                                   -> expect 200
  T2  GET /health                             -> expect 200
  T3  SQL-injection-style search  ' OR 1=1--  -> expect 403 (managed rules)
  T4  XSS-style search  <script>alert('xss')</script> -> expect 403 (managed rules)
  T5  burst of 30 normal requests in < 1 min  -> later requests 403 (RateLimitDemo)
  T6  wait for the rate-limit window to pass, GET / again -> expect 200

Every step prints a PASS/FAIL line with a UTC timestamp; everything is also written
to a results file (default: waf_test_results_<UTC time>.txt in the current folder).
"""

import argparse
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone

USER_AGENT = "ATDR-waf-tests/1.0 (college project; own gateway only)"
SQLI = "' OR 1=1--"
XSS = "<script>alert('xss')</script>"
BURST = 30
RATE_WINDOW_SECONDS = 60


def t5_verdict(statuses, elapsed):
    """T5 passes when the burst starts allowed and RateLimitDemo blocks later requests.

    The gateway runs more than one instance and each keeps its own rate-limit count, so
    once blocking starts the 403s can alternate with 200s (observed 2026-10-23: all
    blocks on instance appgw_0). Requiring every later request to be 403 would be wrong.
    """
    first_block = next((i + 1 for i, s in enumerate(statuses) if s == 403), None)
    ok = (first_block is not None and first_block > 10
          and all(s == 200 for s in statuses[:10]) and elapsed < 60)
    return ok, first_block


def utc_now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"


class Run:
    def __init__(self, base_url, out_path):
        self.base = base_url.rstrip("/")
        self.out = open(out_path, "w", encoding="utf-8")
        self.results = []

    def log(self, line):
        print(line, flush=True)
        self.out.write(line + "\n")
        self.out.flush()

    def get(self, path, params=None):
        url = self.base + path
        if params:
            url += "?" + urllib.parse.urlencode(params)
        req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "text/html,application/json"})
        try:
            with urllib.request.urlopen(req, timeout=15) as resp:
                return resp.status
        except urllib.error.HTTPError as e:
            return e.code
        except (urllib.error.URLError, OSError) as e:
            return "ERR:{}".format(getattr(e, "reason", e))

    def check(self, test_id, description, status, expected):
        ok = status == expected
        self.results.append((test_id, ok))
        self.log("[{}] {} {:<4} {} -> HTTP {} (expected {})".format(
            utc_now(), "PASS" if ok else "FAIL", test_id, description, status, expected))
        return ok

    def close(self):
        passed = sum(1 for _, ok in self.results if ok)
        self.log("[{}] SUMMARY {}/{} passed: {}".format(
            utc_now(), passed, len(self.results),
            ", ".join("{}={}".format(t, "PASS" if ok else "FAIL") for t, ok in self.results)))
        self.out.close()
        return passed == len(self.results)


def main():
    ap = argparse.ArgumentParser(description="ATDR WAF tests T1-T6 (own gateway only)")
    ap.add_argument("url", help="gateway URL, e.g. http://20.0.0.1/")
    ap.add_argument("--out", default="waf_test_results_{}.txt".format(
        datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")))
    args = ap.parse_args()

    if not args.url.startswith(("http://", "https://")):
        ap.error("URL must start with http:// or https://")

    run = Run(args.url, args.out)
    run.log("[{}] ATDR WAF tests against {} (results file: {})".format(utc_now(), run.base, args.out))

    run.check("T1", "normal page GET /", run.get("/"), 200)
    run.check("T2", "health check GET /health", run.get("/health"), 200)
    run.check("T3", "SQL-injection-style search {!r}".format(SQLI), run.get("/products", {"search": SQLI}), 403)
    run.check("T4", "XSS-style search {!r}".format(XSS), run.get("/products", {"search": XSS}), 403)

    run.log("[{}] INFO T5   sending {} normal requests (GET /products?search=lock) as fast as possible".format(utc_now(), BURST))
    t5_start = time.monotonic()
    statuses = [run.get("/products", {"search": "lock"}) for _ in range(BURST)]
    elapsed = time.monotonic() - t5_start
    t5_ok, first_block = t5_verdict(statuses, elapsed)
    run.log("[{}] INFO T5   statuses in order: {}".format(utc_now(), " ".join(str(s) for s in statuses)))
    run.log("[{}] INFO T5   {} requests in {:.1f}s; 200s={} 403s={} first 403 at burst request #{}".format(
        utc_now(), BURST, elapsed, statuses.count(200), statuses.count(403), first_block))
    if first_block and 200 in statuses[first_block:]:
        run.log("[{}] INFO T5   403s alternate with 200s: the gateway has several instances and each "
                "counts requests separately".format(utc_now()))
    run.results.append(("T5", t5_ok))
    run.log("[{}] {} T5   burst: first 10 requests 200, later requests 403 from RateLimitDemo".format(
        utc_now(), "PASS" if t5_ok else "FAIL"))

    # T6: the rate-limit block lasts for the rest of the 1-minute window; wait it out.
    wait = RATE_WINDOW_SECONDS + 10
    run.log("[{}] INFO T6   waiting {}s for the rate-limit window to pass".format(utc_now(), wait))
    time.sleep(wait)
    status = run.get("/")
    for _ in range(2):  # up to two retries, 30 s apart, if still inside the window
        if status == 200:
            break
        run.log("[{}] INFO T6   got HTTP {}, retrying in 30s".format(utc_now(), status))
        time.sleep(30)
        status = run.get("/")
    run.check("T6", "normal page again after the burst GET /", status, 200)

    sys.exit(0 if run.close() else 1)


if __name__ == "__main__":
    main()
