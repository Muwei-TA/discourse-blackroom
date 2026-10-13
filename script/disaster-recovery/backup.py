#!/usr/bin/env python3
"""Encrypted R2 backup of a verified recovery set; no automatic deletion or pruning."""
import datetime
import fcntl
import json
import os
import subprocess
import sys
import time
from pathlib import Path

from capture import ROOT, capture, digest
from compact import compact

RESTIC = Path('/home/muwei/discourse-docker-preview/resilience/offsite/bin/restic')
CONFIG = ROOT / 'private/r2.json'


def restic_env():
    if not CONFIG.is_file() or CONFIG.stat().st_mode & 0o077:
        raise ValueError('Protected R2 configuration required')
    config = json.loads(CONFIG.read_text())
    password = Path(config['password_file'])
    if not config.get('key_escrow_confirmed') or not password.is_file() or password.stat().st_mode & 0o077:
        raise ValueError('Protected password and independent key escrow required')
    expected = 's3:https://841556b7f158ae0bc937a144cefbcb3b.r2.cloudflarestorage.com/blackroom-disaster-recovery/restic'
    if config['repository'] != expected:
        raise ValueError('Unexpected cloud repository')
    env = dict(os.environ)
    env.update(RESTIC_REPOSITORY=expected, RESTIC_PASSWORD_FILE=str(password),
               AWS_ACCESS_KEY_ID=config['access_key_id'], AWS_SECRET_ACCESS_KEY=config['secret_access_key'],
               AWS_DEFAULT_REGION='auto', GOMAXPROCS='2', RESTIC_CACHE_DIR=str(ROOT / 'cache'))
    return env


def run_restic(args, env):
    result = subprocess.run([str(RESTIC), *args], env=env, capture_output=True, text=True)
    with (ROOT / 'restic.private.log').open('a') as log:
        log.write(result.stdout)
        log.write(result.stderr)
    return result


def verify_set(path):
    manifest = json.loads((path / 'manifest.json').read_text())
    for item in manifest['files']:
        relative = Path(item['path'])
        if not item['path'] or relative.name != item['path'] or item['path'] in {'.', '..'}:
            raise ValueError('Invalid manifest path')
        target = path / relative
        if target.is_symlink() or not target.is_file() or target.stat().st_size != item['size'] or digest(target) != item['sha256']:
            raise ValueError('Recovery set checksum mismatch')
    return manifest


def backup(existing=None):
    os.umask(0o077)
    ROOT.mkdir(parents=True, exist_ok=True)
    status = {'started_at': time.time(), 'complete': False, 'cloud_uploaded': False, 'cloud_checked': False}
    with (ROOT / 'backup.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        env = restic_env()
        probe = run_restic(['snapshots', '--json'], env)
        if probe.returncode == 10:
            if run_restic(['init'], env).returncode:
                raise ValueError('Cloud repository initialization failed; protected log retained')
        elif probe.returncode:
            raise ValueError('Cloud repository access failed; protected log retained')
        path = Path(existing) if existing else Path(compact(capture()[0])['capture_path'])
        if path.parent != ROOT or path.name.endswith('.partial'):
            raise ValueError('Only completed local recovery sets can be uploaded')
        manifest = verify_set(path)
        if manifest.get('variant') != 'zstd-models-redownload' or any(
                item['path'].startswith('forum-models.tar') for item in manifest['files']):
            raise ValueError('Only the approved reduced format without model weights may be uploaded')
        result = run_restic(['backup', '--json', '--host', 'blackroom-nas', '--tag', 'blackroom-dr',
                             '--tag', manifest['capture_id'], str(path)], env)
        if result.returncode:
            raise ValueError('Cloud upload incomplete; local recovery set retained')
        summaries = [json.loads(line) for line in result.stdout.splitlines() if line.strip().startswith('{')]
        summary = next(item for item in reversed(summaries) if item.get('message_type') == 'summary')
        status.update(capture_id=manifest['capture_id'], snapshot_id=summary['snapshot_id'],
                      manifest_sha256=digest(path / 'manifest.json'), capture_path=str(path), cloud_uploaded=True,
                      data_added=summary.get('data_added'), forum_backup_completed_at=manifest['forum_backup_completed_at'])
        # Structural check is automatic; full cloud read/download/restore is a separate recorded rehearsal.
        if run_restic(['check'], env).returncode:
            raise ValueError('Cloud repository check failed; local recovery set retained')
        status.update(cloud_checked=True, complete=True, completed_at=time.time())
        temp = ROOT / 'status.json.part'
        temp.write_text(json.dumps(status, indent=2))
        temp.replace(ROOT / 'status.json')
        print(json.dumps(status))
        return status


if __name__ == '__main__':
    try:
        backup(sys.argv[1] if len(sys.argv) > 1 else None)
    except Exception as error:
        error_status = {'complete': False, 'failed_at': time.time(), 'error_type': type(error).__name__}
        ROOT.mkdir(parents=True, exist_ok=True)
        (ROOT / 'last-failure.json').write_text(json.dumps(error_status))
        print(json.dumps(error_status))
        raise SystemExit(1)
