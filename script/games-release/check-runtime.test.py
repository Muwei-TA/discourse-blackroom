import importlib.util
import json
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("runtime", Path(__file__).with_name("check-runtime.py"))
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)


class RuntimeTests(unittest.TestCase):
    def fake_run(self, command, **kwargs):
        self.assertNotIn("{{json .}}", command)
        if "stats" in command:
            value = {"cpu": "0.1%", "memory": "1MiB / 256MiB", "memory_percent": "1%", "pids": "2"}
        else:
            value = {"running": command[-1] != self.down, "status": "running",
                     "oom_killed": False, "exit_code": 0, "restarts": self.restarts,
                     "image": "sha256:test", "memory_limit": 268435456, "nano_cpus": 500000000, "pids_limit": 64}
        return subprocess.CompletedProcess(command, 0, json.dumps(value))

    def test_down_and_http_failure_are_errors_without_leaking_response(self):
        self.down, self.restarts = runtime.CONTAINERS[1], 0
        result = runtime.collect("unix:///test.sock", self.fake_run, lambda url, host: 200)
        self.assertIn(f"{self.down}: not running", result["errors"])
        self.assertTrue(any("bonk: HTTP check failed" in error for error in result["errors"]))
        def broken(*args, **kwargs):
            raise subprocess.CalledProcessError(1, "docker", stderr="secret-do-not-log")
        result = runtime.collect("unix:///test.sock", broken, lambda url, host: 503)
        self.assertNotIn("secret-do-not-log", json.dumps(result))
        self.assertTrue(result["errors"])

    def test_private_files_only_log_changes_and_detect_restart(self):
        self.down, self.restarts = None, 0
        def sample():
            return runtime.collect("unix:///test.sock", self.fake_run,
                                   lambda url, host: 200 if "srv/status" in url else 401)
        with tempfile.TemporaryDirectory() as directory:
            self.assertTrue(runtime.persist(sample(), directory))
            logfile = Path(directory) / "changes.jsonl"
            first = logfile.read_text()
            second = sample()
            second["containers"]["app"]["usage"]["cpu"] = "0.2%"
            self.assertTrue(runtime.persist(second, directory))
            self.assertEqual(first, logfile.read_text())
            self.restarts = 1
            self.assertFalse(runtime.persist(sample(), directory))
            self.assertEqual(len(logfile.read_text().splitlines()), 2)
            for name in ("status.json", "changes.jsonl"):
                self.assertEqual(stat.S_IMODE((Path(directory) / name).stat().st_mode), 0o600)


if __name__ == "__main__":
    unittest.main()
