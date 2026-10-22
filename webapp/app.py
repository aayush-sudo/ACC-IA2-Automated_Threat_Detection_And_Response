"""ATDR Demo Portal — a deliberately small Flask app for the WAF to protect.

Routes:
  /                 landing page
  /health           JSON health check (used by the Application Gateway probe)
  /products?search= harmless product search that echoes the (escaped) input
  /login            demo form; performs no authentication and never logs passwords

Every request is logged as one JSON line to stdout (journald on the VM) with
timestamp, request_id, method, path, status, client_ip and duration_ms.
Query strings, form bodies, cookies and headers other than X-Forwarded-For are
never logged.
"""

import json
import logging
import sys
import time
import uuid
from datetime import datetime, timezone

from flask import Flask, g, jsonify, render_template_string, request

PRODUCTS = [
    {"id": 1, "name": "Security Camera", "price": 49.99},
    {"id": 2, "name": "Smart Door Lock", "price": 89.00},
    {"id": 3, "name": "Network Firewall Appliance", "price": 299.00},
    {"id": 4, "name": "USB Security Key", "price": 25.50},
    {"id": 5, "name": "Wi-Fi Router", "price": 74.25},
]

MAX_SEARCH_LEN = 100

BASE = """<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{{ title }} · ATDR Demo Portal</title>
  <style>
    body { font-family: system-ui, sans-serif; margin: 0; background: #f4f6fb; color: #1d2433; }
    header { background: #0b3d91; color: #fff; padding: 16px 24px; }
    header a { color: #fff; margin-right: 16px; text-decoration: none; }
    main { max-width: 760px; margin: 24px auto; padding: 0 16px; }
    .card { background: #fff; border-radius: 8px; padding: 20px; box-shadow: 0 1px 3px rgba(0,0,0,.1); }
    input, button { font-size: 1rem; padding: 6px 10px; }
    table { width: 100%; border-collapse: collapse; } td, th { padding: 6px; border-bottom: 1px solid #e3e7ef; text-align: left; }
    .note { color: #5a6478; font-size: .9rem; }
  </style>
</head>
<body>
  <header><strong>ATDR Demo Portal</strong> &nbsp;
    <a href="/">Home</a><a href="/products">Products</a><a href="/login">Login</a></header>
  <main><div class="card">{{ body|safe }}</div></main>
</body>
</html>"""

HOME = """<h1>ATDR Demo Portal</h1>
<p>This portal is the protected test application for the college project
<em>Automated Threat Detection and Response Using Microsoft Azure</em>.</p>
<p>Traffic reaches it only through an Azure Application Gateway with a Web
Application Firewall. Blocked attacks are logged to Microsoft Sentinel, which
can trigger an automated containment playbook.</p>
<p class="note">Demo system — no real data or accounts.</p>"""

PRODUCTS_TPL = """<h1>Products</h1>
<form method="get" action="/products">
  <input name="search" value="{{ search }}" maxlength="100" placeholder="Search products">
  <button type="submit">Search</button>
</form>
{% if search %}<p>Results for: <strong>{{ search }}</strong></p>{% endif %}
<table><tr><th>Product</th><th>Price (USD)</th></tr>
{% for p in results %}<tr><td>{{ p.name }}</td><td>{{ '%.2f'|format(p.price) }}</td></tr>
{% else %}<tr><td colspan="2">No products found.</td></tr>{% endfor %}
</table>"""

LOGIN_TPL = """<h1>Login</h1>
{% if submitted %}<p>Demo only: no authentication was performed and nothing was stored.</p>{% endif %}
<form method="post" action="/login">
  <p><label>Username <input name="username" maxlength="50" autocomplete="off"></label></p>
  <p><label>Password <input name="password" type="password" maxlength="100"></label></p>
  <button type="submit">Sign in</button>
</form>
<p class="note">This form is a demo for the WAF. It never checks or logs passwords.</p>"""


class JsonFormatter(logging.Formatter):
    def format(self, record):
        entry = getattr(record, "access", None) or {"message": record.getMessage()}
        entry.setdefault("timestamp", datetime.now(timezone.utc).isoformat(timespec="milliseconds"))
        entry.setdefault("level", record.levelname)
        return json.dumps(entry, separators=(",", ":"))


def client_ip_from(xff, remote_addr):
    """First address in X-Forwarded-For (the original client), port removed.

    Application Gateway v2 appends "ip:port" (e.g. 203.0.113.7:51234).
    """
    if not xff:
        return remote_addr
    first = xff.split(",")[0].strip()
    if first.startswith("["):  # [IPv6]:port
        return first[1:].split("]")[0]
    if first.count(":") == 1:  # IPv4:port
        return first.split(":")[0]
    return first or remote_addr


def create_app():
    app = Flask(__name__)

    logger = logging.getLogger("atdr.access")
    if not logger.handlers:
        handler = logging.StreamHandler(sys.stdout)
        handler.setFormatter(JsonFormatter())
        logger.addHandler(handler)
        logger.setLevel(logging.INFO)
        logger.propagate = False

    def page(title, body_tpl, **ctx):
        body = render_template_string(body_tpl, **ctx)
        return render_template_string(BASE, title=title, body=body)

    @app.before_request
    def start_timer():
        g.start = time.perf_counter()
        g.request_id = str(uuid.uuid4())

    @app.after_request
    def access_log(response):
        response.headers["X-Request-ID"] = g.request_id
        response.headers["X-Content-Type-Options"] = "nosniff"
        logger.info("access", extra={"access": {
            "timestamp": datetime.now(timezone.utc).isoformat(timespec="milliseconds"),
            "request_id": g.request_id,
            "method": request.method,
            "path": request.path,  # path only: no query string, no body
            "status": response.status_code,
            "client_ip": client_ip_from(request.headers.get("X-Forwarded-For"), request.remote_addr),
            "duration_ms": round((time.perf_counter() - g.start) * 1000, 2),
        }})
        return response

    @app.get("/")
    def home():
        return page("Home", HOME)

    @app.get("/health")
    def health():
        return jsonify(status="ok", service="atdr-demo-portal")

    @app.get("/products")
    def products():
        search = request.args.get("search", "")[:MAX_SEARCH_LEN].strip()
        results = [p for p in PRODUCTS if search.lower() in p["name"].lower()]
        # Jinja autoescaping (render_template_string) HTML-escapes `search`.
        return page("Products", PRODUCTS_TPL, search=search, results=results)

    @app.route("/login", methods=["GET", "POST"])
    def login():
        # Form fields are intentionally never read, stored or logged.
        return page("Login", LOGIN_TPL, submitted=request.method == "POST")

    return app


app = create_app()

if __name__ == "__main__":
    app.run(host="127.0.0.1", port=8080)
