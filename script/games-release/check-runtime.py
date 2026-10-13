#!/usr/bin/env python3
"""Read-only NAS checks; persist private status and changes, never repair services."""
import argparse
import datetime
import json
import os
from pathlib import Path
import subprocess
import tempfile
import urllib.error
import urllib.request

CONTAINERS = (
    "blackroom-games-gateway-freeboardgames",
    "freeboardgames-20261013-gateway-1",
    "freeboardgames-20261013-web-1",
    "freeboardgames-20261013-bgio-1",
    "freeboardgames-20261013-backend-1",
    "freeboardgames-20261013-postgres-1",
    "freeboardgames-20261013-redis-1",
    "app",
    "blackroom-games-gateway-bonk",
    "blackroom-games-gateway-skribbl",
    "blackroom_bonkio-game-1",
    "skribblrsio-skribblrs-1",
    "blackroom-games-gateway-drawpile",
    "blackroom-drawpile-web",
    "dpserver-drawpile-srv-1",
)
INSPECT = (
    '{"running":{{json .State.Running}},"status":{{json .State.Status}},'
    '"oom_killed":{{json .State.OOMKilled}},"exit_code":{{json .State.ExitCode}},'
    '"restarts":{{json .RestartCount}},"image":{{json .Image}},'
    '"memory_limit":{{json .HostConfig.Memory}},"nano_cpus":{{json .HostConfig.NanoCpus}},'
    '"pids_limit":{{json .HostConfig.PidsLimit}}}'
)
STATS = (
    '{"cpu":{{json .CPUPerc}},"memory":{{json .MemUsage}},'
    '"memory_percent":{{json .MemPerc}},"pids":{{json .PIDs}}}'
)
ENDPOINTS = (
    ("freeboardgames", "http://172.16.243.6:8080/", "boardgames.muwei.xyz", 401),
    ("forum", "http://192.168.50.28:18180/srv/status", "discourse.muwei.xyz", 200),
    ("bonk", "http://172.16.243.2:8080/", "bonk.muwei.xyz", 401),
    ("skribbl", "http://172.16.243.3:8080/", "skribbl.muwei.xyz", 401),
    ("drawpile", "http://172.16.243.5:8080/", "drawpile.muwei.xyz", 401),
)


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def http_status(url, host):
    # Ignore host proxy environment: these are exact NAS internal endpoints.
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
    try:
        with opener.open(urllib.request.Request(url, headers={"Host": host}), timeout=5) as response:
            return response.status
    except urllib.error.HTTPError as error:
        status = error.code
        error.close()
        return status


def collect(docker_host, run=subprocess.run, request=http_status):
    result = {"containers": {}, "http": {}, "errors": []}
    for name in CONTAINERS:
        entry = {}
        try:
            command = ["docker", "--host", docker_host]
            inspected = run(command + ["inspect", "--format", INSPECT, name],
                            capture_output=True, text=True, check=True, timeout=10)
            entry = json.loads(inspected.stdout)
            if not entry["running"]:
                result["errors"].append(f"{name}: not running")
            if entry["oom_killed"]:
                result["errors"].append(f"{name}: OOM killed")
            if entry["running"]:
                stats = run(command + ["stats", "--no-stream", "--format", STATS, name],
                            capture_output=True, text=True, check=True, timeout=10)
                entry["usage"] = json.loads(stats.stdout)
        except (OSError, subprocess.SubprocessError, ValueError, KeyError):
            # Do not copy Docker stderr or HTTP bodies into operational logs.
            result["errors"].append(f"{name}: Docker check failed")
        result["containers"][name] = entry
    for name, url, host, expected in ENDPOINTS:
        try:
            status = request(url, host)
        except (OSError, urllib.error.URLError, ValueError):
            status = None
        result["http"][name] = {"status": status, "expected": expected}
        if status != expected:
            result["errors"].append(f"{name}: HTTP check failed (expected {expected}, got {status})")
    return result


def meaningful(result):
    return {
        "containers": {name: {k: v for k, v in entry.items() if k != "usage"}
                       for name, entry in result.get("containers", {}).items()},
        "http": result.get("http", {}),
        "errors": result.get("errors", []),
    }


def persist(result, directory):
    directory = Path(directory)
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    status_path = directory / "status.json"
    try:
        previous = json.loads(status_path.read_text())
    except (OSError, ValueError):
        previous = {}
    for name, entry in result["containers"].items():
        before = previous.get("containers", {}).get(name, {})
        if entry.get("restarts", 0) > before.get("restarts", entry.get("restarts", 0)):
            result["errors"].append(f"{name}: restart count increased")
    result["checked_at"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    result["ok"] = not result["errors"]
    payload = json.dumps(result, ensure_ascii=False, sort_keys=True) + "\n"
    fd, temporary = tempfile.mkstemp(prefix=".status-", dir=directory)
    try:
        with os.fdopen(fd, "w") as handle:
            handle.write(payload)
        os.replace(temporary, status_path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    if result["errors"] or meaningful(previous) != meaningful(result):
        fd = os.open(directory / "changes.jsonl", os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
        with os.fdopen(fd, "a") as handle:
            os.fchmod(handle.fileno(), 0o600)
            handle.write(payload)
    return result["ok"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--docker-host", default="unix:///var/run/docker.sock")
    args = parser.parse_args()
    ok = persist(collect(args.docker_host), args.output_dir)
    print("Game runtime checks: " + ("OK" if ok else "FAILED; see private status.json"))
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
