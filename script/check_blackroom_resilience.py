#!/usr/bin/env python3
"""Verify and copy BlackRoom backups from vol1 to the user-selected vol4."""

import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = Path("/vol4/1000/backup/blackroom")
SOURCE = Path("/vol1/docker/discourse-preview/shared/backups/default")


def run(args, check=True):
    return subprocess.run(args, check=check, stdin=subprocess.DEVNULL,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)


def inspect_nas():
    state = run(["docker", "inspect", "app", "--format", "{{.State.Running}} {{.RestartCount}}"])
    pg = run(["docker", "exec", "app", "pg_isready", "-q"], check=False)
    redis = run(["docker", "exec", "app", "redis-cli", "ping"], check=False)
    jobs = run(["docker", "exec", "app", "pgrep", "-f", "sidekiq"], check=False)
    web = run(["curl", "-sS", "--max-time", "10", "-H", "Host: discourse.muwei.xyz",
               "-H", "X-Forwarded-Proto: https", "-o", "/dev/null", "-w", "%{http_code}",
               "http://192.168.50.28:18180/srv/status"], check=False)
    backups = []
    for path in SOURCE.glob("*.tar.gz"):
        stat = path.stat()
        # Native gzip may still be creating its final filename.
        if time.time() - stat.st_mtime >= 120:
            backups.append({"name": path.name, "size": stat.st_size, "mtime": stat.st_mtime})
    disk = shutil.disk_usage(SOURCE)
    return {"container": state.stdout.decode().strip(), "database": pg.returncode == 0,
        "redis": redis.stdout.strip() == b"PONG", "background_jobs": jobs.returncode == 0,
        "origin_http": web.stdout.decode().strip(),
        "disk_used_percent": round(disk.used / disk.total * 100, 1),
        "backups": sorted(backups, key=lambda backup: backup["mtime"], reverse=True)}


def checksum(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verify_backup(path, expected):
    digest = checksum(path)
    if digest != expected:
        raise ValueError("Backup checksum mismatch")
    run(["/usr/bin/gzip", "-t", str(path)])
    with tarfile.open(path, "r:gz") as archive:
        members = archive.getnames()
    if not any(name.endswith("dump.sql.gz") for name in members):
        raise ValueError("Database dump missing from backup")
    return digest


def main():
    os.umask(0o077)
    if not os.path.ismount("/vol4") or os.stat("/vol4").st_dev == os.stat("/vol1").st_dev:
        raise SystemExit("Backup volume vol4 is missing or not independent of vol1")
    ROOT.mkdir(parents=True, exist_ok=True)
    with (ROOT / "check.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return 0
        status = {"checked_at": time.time(), "errors": [], "copied": []}
        try:
            nas = inspect_nas()
            status["nas"] = nas
            for key in ("database", "redis", "background_jobs"):
                if not nas[key]:
                    status["errors"].append(key + " unavailable")
            if not nas["container"].startswith("true "):
                status["errors"].append("container unavailable")
            if nas["origin_http"] != "200":
                status["errors"].append("origin unavailable")
            if nas["disk_used_percent"] >= 90:
                status["errors"].append("vol1 disk usage above 90 percent")
            daily = ROOT / "daily"
            daily.mkdir(parents=True, exist_ok=True)
            for backup in nas["backups"]:
                name = backup["name"]
                if not re.fullmatch(r"[A-Za-z0-9_.-]+\.tar\.gz", name):
                    raise ValueError("Unexpected backup filename")
                target = daily / name
                receipt = daily / (name + ".json")
                if target.exists() and receipt.exists():
                    saved = json.loads(receipt.read_text())
                    if saved["mtime"] == backup["mtime"] and target.stat().st_size == backup["size"]:
                        if backup == nas["backups"][0]:
                            verify_backup(target, saved["sha256"])
                        continue
                    raise ValueError("Previously copied backup changed")
                expected = checksum(SOURCE / name)
                temp = daily / (name + ".part")
                shutil.copyfile(SOURCE / name, temp)
                digest = verify_backup(temp, expected)
                temp.replace(target)
                receipt.write_text(json.dumps({**backup, "sha256": digest}))
                status["copied"].append(name)
            backups = nas["backups"]
            if not backups or time.time() - backups[0]["mtime"] > 26 * 3600:
                status["errors"].append("no complete backup within 26 hours")
            status["vol4_copy_verified"] = bool(backups) and (daily / (backups[0]["name"] + ".json")).exists()
            if shutil.disk_usage(ROOT).free < 10 * 1024**3:
                status["errors"].append("vol4 has less than 10 GiB free")
        except (subprocess.SubprocessError, OSError, ValueError, KeyError, tarfile.TarError):
            status["errors"].append("NAS check or verified backup copy failed")
        try:
            with urllib.request.urlopen("https://discourse.muwei.xyz", timeout=15) as response:
                status["public_http"] = response.status
                status["public_final_host"] = urllib.parse.urlparse(response.url).hostname
        except (urllib.error.URLError, OSError):
            status["errors"].append("public gateway request failed")
        temp_status = ROOT / "status.json.part"
        temp_status.write_text(json.dumps(status, ensure_ascii=False, indent=2))
        temp_status.replace(ROOT / "status.json")
        print(json.dumps(status, ensure_ascii=False))
        return bool(status["errors"])


if __name__ == "__main__":
    raise SystemExit(main())
