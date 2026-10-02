#!/usr/bin/env python3
"""ServerPulse metrics agent: host and Docker container status over HTTP (stdlib only)."""
import hmac
import http.client
import json
import math
import os
import socket
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

VERSION = 2
PROC = os.environ.get("PROC_ROOT", "/proc")
HOST_ROOT = os.environ.get("HOST_ROOT", "/host-root")
DOCKER_SOCK = os.environ.get("DOCKER_SOCK", "/var/run/docker.sock")
SAMPLE_INTERVAL = 5.0
HEALTH_VALUES = ("healthy", "unhealthy", "starting")


def read(path):
    with open(path) as f:
        return f.read()


def safe(fn):
    try:
        return fn()
    except (OSError, ValueError, IndexError, KeyError):
        return None


# --- host metrics -----------------------------------------------------------

def parse_cpu_times(text):
    """Aggregate `cpu` line of /proc/stat -> (busy, total) jiffies. iowait counts as idle."""
    fields = [int(v) for v in text.splitlines()[0].split()[1:9]]
    total = sum(fields)
    idle = fields[3] + fields[4]
    return total - idle, total


def cpu_pct(prev, cur):
    if prev is None or cur is None:
        return None
    d_total = cur[1] - prev[1]
    if d_total <= 0:
        return None
    return round(100.0 * (cur[0] - prev[0]) / d_total, 1)


def parse_meminfo(text):
    values = {}
    for line in text.splitlines():
        key, _, rest = line.partition(":")
        values[key] = int(rest.split()[0])
    total = values["MemTotal"]
    return (total - values["MemAvailable"]) // 1024, total // 1024


def parse_loadavg(text):
    return float(text.split()[0])


def parse_uptime(text):
    return int(float(text.split()[0]))


def disk_used_pct(path, statvfs=os.statvfs):
    st = statvfs(path)
    used = st.f_blocks - st.f_bfree
    denom = used + st.f_bavail
    if denom <= 0:
        return None
    return math.ceil(100.0 * used / denom)


def hostname():
    name = safe(lambda: read(f"{HOST_ROOT}/etc/hostname").strip())
    return name or socket.gethostname()


class CpuSampler(threading.Thread):
    def __init__(self, interval=SAMPLE_INTERVAL):
        super().__init__(daemon=True)
        self.interval = interval
        self._lock = threading.Lock()
        self._pct = None

    def pct(self):
        with self._lock:
            return self._pct

    def run(self):
        prev = safe(lambda: parse_cpu_times(read(f"{PROC}/stat")))
        while True:
            time.sleep(self.interval)
            cur = safe(lambda: parse_cpu_times(read(f"{PROC}/stat")))
            value = cpu_pct(prev, cur)
            with self._lock:
                self._pct = value
            prev = cur


# --- docker -----------------------------------------------------------------

class UnixHTTPConnection(http.client.HTTPConnection):
    def __init__(self, path, timeout=5):
        super().__init__("localhost", timeout=timeout)
        self.unix_path = path

    def connect(self):
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(self.timeout)
        sock.connect(self.unix_path)
        self.sock = sock


def parse_health(status):
    if "(unhealthy)" in status:
        return "unhealthy"
    if "(healthy)" in status:
        return "healthy"
    if "(health: starting)" in status:
        return "starting"
    return None


def parse_containers(items):
    out = []
    for c in items:
        status = c.get("Status") or ""
        health = (c.get("Health") or {}).get("Status") or parse_health(status)
        out.append({
            "name": ((c.get("Names") or ["?"])[0]).lstrip("/"),
            "project": (c.get("Labels") or {}).get("com.docker.compose.project"),
            "state": c.get("State") or "unknown",
            "health": health if health in HEALTH_VALUES else None,
            "status": status,
        })
    return sorted(out, key=lambda c: c["name"])


def fetch_containers(sock_path=DOCKER_SOCK):
    conn = UnixHTTPConnection(sock_path)
    try:
        conn.request("GET", "/containers/json?all=1")
        resp = conn.getresponse()
        body = resp.read()
        if resp.status != 200:
            raise RuntimeError(f"Docker API returned {resp.status}")
        return parse_containers(json.loads(body))
    finally:
        conn.close()


# --- assembly + HTTP --------------------------------------------------------

def collect(cpu_pct_fn, fetch_containers_fn=fetch_containers):
    mem = safe(lambda: parse_meminfo(read(f"{PROC}/meminfo"))) or (None, None)
    try:
        containers, docker_error = fetch_containers_fn(), None
    except Exception as e:  # noqa: BLE001 - any Docker failure is reported, host metrics still served
        containers, docker_error = None, str(e) or e.__class__.__name__
    return {
        "version": VERSION,
        "hostname": hostname(),
        "uptime_s": safe(lambda: parse_uptime(read(f"{PROC}/uptime"))),
        "cpu": {
            "cores": os.cpu_count(),
            "pct": cpu_pct_fn(),
            "load_1m": safe(lambda: parse_loadavg(read(f"{PROC}/loadavg"))),
        },
        "memory": {"used_mb": mem[0], "total_mb": mem[1]},
        "disk": {"path": "/", "used_pct": safe(lambda: disk_used_pct(HOST_ROOT))},
        "containers": containers,
        "docker_error": docker_error,
    }


def authorized(header, token):
    if not token:
        return False
    return hmac.compare_digest((header or "").encode(), f"Bearer {token}".encode())


def make_handler(token, collect_fn):
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):  # noqa: N802 - stdlib naming
            if self.path == "/health":
                self._send(200, b"ok", "text/plain")
            elif self.path == "/metrics":
                if not authorized(self.headers.get("Authorization"), token):
                    self._send(401, b'{"error":"unauthorized"}')
                else:
                    self._send(200, json.dumps(collect_fn()).encode())
            else:
                self._send(404, b'{"error":"not found"}')

        def _send(self, code, body, ctype="application/json"):
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, fmt, *args):
            if args and "/health" in str(args[0]):
                return
            sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

    return Handler


def main():
    token = os.environ.get("METRICS_TOKEN", "")
    if not token:
        raise SystemExit("METRICS_TOKEN is not set")
    sampler = CpuSampler()
    sampler.start()
    port = int(os.environ.get("PORT", "5000"))
    server = ThreadingHTTPServer(("0.0.0.0", port), make_handler(token, lambda: collect(sampler.pct)))
    server.serve_forever()


if __name__ == "__main__":
    main()
