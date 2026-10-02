import http.client
import json
import threading
import unittest
from http.server import ThreadingHTTPServer

import agent

PROC_STAT_A = "cpu  100 0 50 800 50 0 0 0 0 0\ncpu0 50 0 25 400 25 0 0 0 0 0\n"
PROC_STAT_B = "cpu  130 0 70 840 60 0 0 0 0 0\ncpu0 65 0 35 420 30 0 0 0 0 0\n"
MEMINFO = "MemTotal:        3910656 kB\nMemFree:          159744 kB\nMemAvailable:    1788928 kB\n"
DOCKER_LIST = [
    {"Names": ["/convex-backend-1"], "State": "running", "Status": "Up 4 days (healthy)",
     "Health": {"Status": "healthy", "FailingStreak": 0},
     "Labels": {"com.docker.compose.project": "convex"}},
    {"Names": ["/web-1"], "State": "running", "Status": "Up 2 hours (unhealthy)", "Labels": {}},
    {"Names": ["/boot-1"], "State": "running", "Status": "Up 3 seconds (health: starting)", "Labels": None},
    {"Names": ["/old-1"], "State": "exited", "Status": "Exited (1) 2 days ago",
     "Labels": {"com.docker.compose.project": "old"}},
    {"Names": ["/paused-1"], "State": "paused", "Status": "Up 1 day (Paused)", "Labels": {}},
    {"Names": ["/none-1"], "State": "running", "Status": "Up 1 day", "Health": {"Status": "none"}},
]


class ParserTests(unittest.TestCase):
    def test_cpu_times_counts_iowait_as_idle(self):
        self.assertEqual(agent.parse_cpu_times(PROC_STAT_A), (150, 1000))

    def test_cpu_pct_from_two_samples(self):
        a = agent.parse_cpu_times(PROC_STAT_A)
        b = agent.parse_cpu_times(PROC_STAT_B)
        # A: busy 150 / total 1000; B: busy 200 / total 1100 -> 50 of 100 jiffies busy
        self.assertEqual(agent.cpu_pct(a, b), 50.0)

    def test_cpu_pct_none_without_progress(self):
        a = agent.parse_cpu_times(PROC_STAT_A)
        self.assertIsNone(agent.cpu_pct(a, a))
        self.assertIsNone(agent.cpu_pct(None, a))

    def test_meminfo(self):
        self.assertEqual(agent.parse_meminfo(MEMINFO), (2072, 3819))

    def test_loadavg_and_uptime(self):
        self.assertEqual(agent.parse_loadavg("0.14 0.20 0.25 1/300 1234\n"), 0.14)
        self.assertEqual(agent.parse_uptime("345600.42 600000.00\n"), 345600)

    def test_disk_used_pct_matches_df_rounding(self):
        class St:
            f_blocks, f_bfree, f_bavail = 1000, 300, 250
        self.assertEqual(agent.disk_used_pct("/x", statvfs=lambda _: St()), 74)  # ceil(700/950*100)

    def test_parse_health_from_status(self):
        self.assertEqual(agent.parse_health("Up 4 days (healthy)"), "healthy")
        self.assertEqual(agent.parse_health("Up 2 hours (unhealthy)"), "unhealthy")
        self.assertEqual(agent.parse_health("Up 3 seconds (health: starting)"), "starting")
        self.assertIsNone(agent.parse_health("Up 1 day"))

    def test_parse_containers(self):
        out = agent.parse_containers(DOCKER_LIST)
        by_name = {c["name"]: c for c in out}
        self.assertEqual([c["name"] for c in out], sorted(by_name))
        self.assertEqual(by_name["convex-backend-1"],
                         {"name": "convex-backend-1", "project": "convex", "state": "running",
                          "health": "healthy", "status": "Up 4 days (healthy)"})
        self.assertEqual(by_name["web-1"]["health"], "unhealthy")
        self.assertIsNone(by_name["web-1"]["project"])
        self.assertEqual(by_name["boot-1"]["health"], "starting")
        self.assertEqual(by_name["old-1"]["state"], "exited")
        self.assertIsNone(by_name["paused-1"]["health"])
        self.assertIsNone(by_name["none-1"]["health"])


class AuthTests(unittest.TestCase):
    def test_authorized(self):
        self.assertTrue(agent.authorized("Bearer s3cret", "s3cret"))
        self.assertFalse(agent.authorized("Bearer wrong", "s3cret"))
        self.assertFalse(agent.authorized(None, "s3cret"))
        self.assertFalse(agent.authorized("Bearer ", ""))


class CollectTests(unittest.TestCase):
    def test_docker_failure_keeps_host_metrics(self):
        def boom():
            raise OSError("socket missing")
        out = agent.collect(lambda: 12.5, boom)
        self.assertEqual(out["version"], 2)
        self.assertIsNone(out["containers"])
        self.assertIn("socket missing", out["docker_error"])
        self.assertEqual(out["cpu"]["pct"], 12.5)
        self.assertIn("memory", out)
        self.assertIn("disk", out)

    def test_containers_included(self):
        out = agent.collect(lambda: None, lambda: [{"name": "a"}])
        self.assertEqual(out["containers"], [{"name": "a"}])
        self.assertIsNone(out["docker_error"])


class HTTPTests(unittest.TestCase):
    def setUp(self):
        handler = agent.make_handler("s3cret", lambda: {"version": 2})
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.port = self.server.server_address[1]

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()

    def get(self, path, token=None):
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        headers = {"Authorization": f"Bearer {token}"} if token else {}
        conn.request("GET", path, headers=headers)
        r = conn.getresponse()
        body = r.read()
        conn.close()
        return r.status, body

    def test_health_needs_no_auth(self):
        self.assertEqual(self.get("/health"), (200, b"ok"))

    def test_metrics_requires_token(self):
        self.assertEqual(self.get("/metrics")[0], 401)
        self.assertEqual(self.get("/metrics", "wrong")[0], 401)

    def test_metrics_with_token(self):
        status, body = self.get("/metrics", "s3cret")
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body), {"version": 2})

    def test_unknown_path(self):
        self.assertEqual(self.get("/nope", "s3cret")[0], 404)


if __name__ == "__main__":
    unittest.main()
