#!/usr/bin/env python3
"""Download and verify a cloud recovery set into a new directory, without starting services."""
import argparse
import getpass
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from configure_r2 import ACCOUNT, BUCKET, read_s3_key

REPOSITORY = f's3:https://{ACCOUNT}.r2.cloudflarestorage.com/{BUCKET}/restic'


def verify(path):
    manifest = json.loads((path / 'manifest.json').read_text())
    for item in manifest['files']:
        name = item['path']
        if not name or Path(name).name != name or name in {'.', '..'}:
            raise ValueError('Unsafe recovery manifest path')
        source = path / name
        if source.is_symlink() or not source.is_file() or source.stat().st_size != item['size']:
            raise ValueError('Recovery file missing or wrong size')
        if not verify_single(source, item['size'], item['sha256']):
            raise ValueError('Recovery file checksum mismatch')
    return manifest


def unpack(path, manifest):
    for item in manifest['files']:
        if 'uncompressed_path' not in item:
            continue
        name = item['uncompressed_path']
        if not name or Path(name).name != name or name in {'.', '..'}:
            raise ValueError('Unsafe uncompressed manifest path')
        target = path / name
        temporary = path / (name + '.part')
        if target.exists() or target.is_symlink() or temporary.exists() or temporary.is_symlink():
            raise ValueError('Existing decompressed recovery files are preserved')
        with temporary.open('xb') as stream:
            subprocess.run(['zstd', '-q', '-dc', str(path / item['path'])], stdout=stream, check=True)
        verified = verify_single(temporary, item['uncompressed_size'], item['uncompressed_sha256'])
        if not verified:
            raise ValueError('Decompressed recovery checksum mismatch')
        temporary.rename(target)


def verify_single(path, size, expected):
    if path.stat().st_size != size:
        return False
    sha = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            sha.update(chunk)
    return sha.hexdigest() == expected


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('destination', type=Path)
    parser.add_argument('--snapshot', default='latest')
    parser.add_argument('--use-nas-config', action='store_true')
    args = parser.parse_args()
    destination = args.destination
    if not destination.is_absolute() or destination.exists():
        raise SystemExit('Use an absolute destination that does not exist; existing data is never overwritten.')
    restic = shutil.which('restic') or '/home/muwei/discourse-docker-preview/resilience/offsite/bin/restic'
    os.umask(0o077)
    destination.mkdir(parents=True)
    with tempfile.TemporaryDirectory(prefix='blackroom-recovery-') as temporary:
        env = dict(os.environ)
        env.update(RESTIC_REPOSITORY=REPOSITORY, GOMAXPROCS='2', AWS_DEFAULT_REGION='auto',
                   RESTIC_CACHE_DIR=str(destination / '.restic-cache'))
        if args.use_nas_config:
            from backup import restic_env
            env.update(restic_env())
        else:
            env['AWS_ACCESS_KEY_ID'] = read_s3_key('R2 Access Key ID (hidden): ', 32)
            env['AWS_SECRET_ACCESS_KEY'] = read_s3_key('R2 Secret Access Key (hidden): ', 64)
            password = Path(temporary) / 'password'
            password.write_text(getpass.getpass('Independent recovery passphrase (hidden): ') + '\n')
            env['RESTIC_PASSWORD_FILE'] = str(password)
        log_path = destination / 'restore.private.log'
        with log_path.open('w') as log:
            for command in [
                ['check'],
                ['restore', args.snapshot, '--host', 'blackroom-nas', '--tag', 'blackroom-dr',
                 '--target', str(destination), '--verify'],
            ]:
                result = subprocess.run([restic, *command], env=env, stdout=log, stderr=log)
                if result.returncode:
                    raise SystemExit('Cloud recovery failed; protected log retained in destination.')
        manifests = list(destination.glob('vol4/1000/backup/blackroom/offsite/capture-*/manifest.json'))
        if len(manifests) != 1:
            raise SystemExit('Expected exactly one recovery set; destination retained for inspection.')
        path = manifests[0].parent
        manifest = verify(path)
        unpack(path, manifest)
        result = {'capture_id': manifest['capture_id'], 'recovery_set': str(path),
                  'snapshot_full_read_passed': True, 'checksums_passed': True,
                  'decompressed_checksums_passed': True, 'services_restored': False}
        (destination / 'verification.json').write_text(json.dumps(result, indent=2) + '\n')
        print(json.dumps(result))


if __name__ == '__main__':
    main()
