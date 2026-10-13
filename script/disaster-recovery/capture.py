#!/usr/bin/env python3
"""Capture a private, same-version BlackRoom recovery set on the intended NAS."""
import datetime
import hashlib
import gzip
import json
import os
import shutil
import sqlite3
import subprocess
import tarfile
import time
from pathlib import Path, PurePosixPath

ROOT = Path('/vol4/1000/backup/blackroom/offsite')
DEPLOY = Path('/home/muwei/discourse-docker-preview')
SHARED = Path('/vol1/docker/discourse-preview/shared')
MODELS = Path('/vol2/@apphome/ai_installer/models')
DOCKER = ['docker', '--context', 'default']
SERVICE_DIRS = [
    DEPLOY,
    Path('/home/muwei/docker-apps/blackroom-games-platform'),
    Path('/home/muwei/docker-apps/blackroom_Bonk.io'),
    Path('/home/muwei/docker-apps/Skribblrs.io'),
    Path('/home/muwei/docker-apps/blackroom-drawpile-20261013'),
    Path('/home/muwei/docker-apps/blackroom-freeboardgames-20261013'),
    Path('/home/muwei/docker-apps/freeboardgames-20261013'),
    Path('/home/muwei/blackroom-ollama-proxy'),
    Path('/vol1/1000/docker/dpserver'),
    Path('/vol2/@appdata/dsh/dsh_home/storages/project/vps/pangolin/nas'),
]
MODEL_MANIFESTS = [
    'registry.ollama.ai/library/blackroom-moderator/latest',
    'registry.ollama.ai/library/blackroom-tags-bge-m3/latest',
    'hf.co/tencent/HY-MT1.5-1.8B-GGUF/Q4_K_M',
]


def digest(path):
    value = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(chunk)
    return value.hexdigest()


def command(args, target=None):
    # Command stderr can contain private configuration: keep it inside the recovery set.
    with (target.open('wb') if target else open(os.devnull, 'wb')) as output:
        with (ROOT / 'capture-command.log').open('ab') as errors:
            subprocess.run(args, stdout=output, stderr=errors, check=True)


def archive(target, paths):
    paths = [Path(path) for path in paths]
    for path in paths:
        if not path.exists():
            raise ValueError(f'Required source missing: {path}')
    args = ['tar', '--exclude=.git', '--exclude=node_modules', '--exclude=__pycache__',
            '--exclude=*.log', '--exclude=*.part', '--exclude=._*', '--exclude=resilience',
            '--exclude=postgres_data', '--exclude=redis_data', '--exclude=shared',
            '--exclude=*.db-wal', '--exclude=*.db-shm', '--exclude=config.db', '-cf', '-',
            *[str(path) for path in paths]]
    command(args, target)
    with tarfile.open(target) as bundle:
        if not bundle.getmembers():
            raise ValueError('Empty recovery archive')


def verify_forum_backup(path):
    with gzip.open(path, 'rb') as stream:
        for _ in iter(lambda: stream.read(1024 * 1024), b''):
            pass
    has_dump = False
    uploads = 0
    with tarfile.open(path, 'r:gz') as archive:
        for member in archive:
            name = member.name.removeprefix('./')
            parts = PurePosixPath(name)
            if parts.is_absolute() or '..' in parts.parts or member.issym() or member.islnk():
                raise ValueError('Unsafe forum archive member')
            if not (member.isfile() or member.isdir()):
                raise ValueError('Unexpected forum archive member type')
            if name == 'dump.sql.gz' and member.isfile() and member.size > 0:
                decoded = 0
                with gzip.GzipFile(fileobj=archive.extractfile(member)) as dump:
                    for chunk in iter(lambda: dump.read(1024 * 1024), b''):
                        decoded += len(chunk)
                has_dump = decoded > 0
            uploads += bool(member.isfile() and member.size > 0 and name.startswith('uploads/'))
    if not has_dump or not uploads:
        raise ValueError('A complete forum database + uploads backup is required')
    return uploads


def capture():
    if not (DEPLOY / 'containers/app.yml').exists() or not SHARED.exists():
        raise ValueError('Run only on the intended NAS')
    if not os.path.ismount('/vol4'):
        raise ValueError('Backup volume must be mounted')
    if shutil.disk_usage('/vol4').free < 50 * 1024**3:
        raise ValueError('At least 50 GiB free is required for a complete recovery set')
    os.umask(0o077)
    ROOT.mkdir(parents=True, exist_ok=True)
    capture_id = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    staging = ROOT / ('capture-' + capture_id + '.partial')
    staging.mkdir()
    started = time.time()
    backups = sorted((SHARED / 'backups/default').glob('*.tar.gz'), key=lambda p: p.stat().st_mtime, reverse=True)
    if not backups or started - backups[0].stat().st_mtime > 26 * 3600:
        raise ValueError('No recent complete forum backup')
    backup = backups[0]
    before = (backup.stat().st_size, backup.stat().st_mtime_ns, digest(backup))
    upload_count = verify_forum_backup(backup)
    shutil.copyfile(backup, staging / 'forum-backup.tar.gz')
    if digest(staging / 'forum-backup.tar.gz') != before[2] or before != (backup.stat().st_size, backup.stat().st_mtime_ns, digest(backup)):
        raise ValueError('Forum backup changed during capture')

    names = subprocess.check_output(DOCKER + ['ps', '-a', '--format', '{{.Names}}'], text=True).splitlines()
    selected = [name for name in names if name == 'app' or name == 'newt' or name == 'blackroom-ollama-proxy'
                or name.startswith(('blackroom-games-gateway-', 'blackroom_bonkio-', 'skribblrsio-',
                                    'blackroom-drawpile-web', 'dpserver-', 'freeboardgames-20261013-'))]
    required = {'app', 'newt', 'blackroom-ollama-proxy',
                'blackroom-games-gateway-bonk', 'blackroom-games-gateway-skribbl',
                'blackroom-games-gateway-drawpile', 'blackroom-games-gateway-freeboardgames',
                'blackroom_bonkio-game-1', 'skribblrsio-skribblrs-1', 'blackroom-drawpile-web',
                'dpserver-drawpile-srv-1', 'freeboardgames-20261013-postgres-1',
                'freeboardgames-20261013-redis-1', 'freeboardgames-20261013-backend-1',
                'freeboardgames-20261013-web-1', 'freeboardgames-20261013-bgio-1',
                'freeboardgames-20261013-gateway-1'}
    if not required.issubset(selected):
        raise ValueError('Required production service inventory incomplete')
    command(DOCKER + ['inspect', *selected], staging / 'containers.private.json')
    metadata = json.loads((staging / 'containers.private.json').read_text())
    command(['crontab', '-l'], staging / 'crontab.private.txt')
    archive(staging / 'deployment-and-services.tar', SERVICE_DIRS)
    # Include private files and disabled-task markers; never copy live PostgreSQL data directories.
    command(DOCKER + ['exec', 'app', 'tar', '--exclude=*.log', '--exclude=*.part', '--exclude=._*',
                     '-C', '/shared', '-cf', '-', 'state', 'plugins'], staging / 'forum-state.tar')
    command(DOCKER + ['exec', '-u', 'discourse', 'app', 'bash', '-lc',
                     'cd /var/www/discourse && git diff --binary'], staging / 'core.patch')
    command(DOCKER + ['exec', '-u', 'discourse', 'app', 'git', '-C', '/var/www/discourse', 'rev-parse', 'HEAD'], staging / 'core-revision.txt')

    command(DOCKER + ['exec', 'freeboardgames-20261013-postgres-1', 'sh', '-c',
                     'exec pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc'], staging / 'tabletop.dump')
    with (staging / 'tabletop.dump').open('rb') as stream:
        subprocess.run(DOCKER + ['exec', '-i', 'freeboardgames-20261013-postgres-1', 'pg_restore', '--list'],
                       stdin=stream, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
    command(DOCKER + ['exec', 'freeboardgames-20261013-postgres-1', 'sh', '-c',
                     'exec pg_dumpall -U "$POSTGRES_USER" --globals-only'], staging / 'tabletop-roles.private.sql')
    sqlite_path = Path('/vol1/docker/volumes/dpserver_serverdata/_data/config.db')
    with sqlite3.connect(f'file:{sqlite_path}?mode=ro', uri=True) as source:
        with sqlite3.connect(staging / 'drawpile-config.db') as target:
            source.backup(target)
            if target.execute('pragma integrity_check').fetchone()[0] != 'ok':
                raise ValueError('Drawpile SQLite backup invalid')
    archive(staging / 'drawpile-files.tar', [sqlite_path.parent])
    command(DOCKER + ['exec', 'freeboardgames-20261013-redis-1', 'redis-cli', '--rdb', '/tmp/blackroom-dr.rdb'])
    command(DOCKER + ['cp', 'freeboardgames-20261013-redis-1:/tmp/blackroom-dr.rdb', str(staging / 'tabletop-redis.rdb')])

    model_files = set()
    for relative in MODEL_MANIFESTS:
        path = MODELS / 'manifests' / relative
        data = json.loads(path.read_text())
        model_files.add(path)
        for layer in [data['config'], *data['layers']]:
            blob = MODELS / 'blobs' / layer['digest'].replace(':', '-')
            if not blob.is_file() or digest(blob) != layer['digest'].split(':', 1)[1]:
                raise ValueError('Required model blob missing or corrupt')
            model_files.add(blob)
    # CPU backends retain the forum's inference functions without unrelated CUDA/ROCm libraries.
    runtime = Path('/vol2/@appcenter/ai_installer/ollama')
    model_files.add(runtime / 'bin/ollama')
    model_files.update(path for path in (runtime / 'lib/ollama').iterdir() if path.is_file())
    archive(staging / 'forum-models.tar', sorted(model_files))

    tag = 'local_discourse/app:disaster-recovery-' + capture_id.lower()
    command(DOCKER + ['commit', '--pause=false', 'app', tag], staging / 'forum-image.id')
    snapshot = (staging / 'forum-image.id').read_text().strip()
    images = sorted({item['Image'] for item in metadata} | {snapshot})
    command(DOCKER + ['image', 'save', *images], staging / 'images.tar')
    with tarfile.open(staging / 'images.tar') as images_archive:
        if 'manifest.json' not in images_archive.getnames():
            raise ValueError('Image archive has no manifest')
    command(DOCKER + ['image', 'inspect', *images], staging / 'images.private.json')
    files = [{'path': path.name, 'size': path.stat().st_size, 'sha256': digest(path)}
             for path in sorted(staging.iterdir()) if path.is_file()]
    manifest = {
        'capture_id': capture_id, 'started_at': started, 'completed_at': time.time(),
        'forum_backup_completed_at': backup.stat().st_mtime, 'forum_backup_name': backup.name,
        'forum_upload_members': upload_count, 'core_revision': (staging / 'core-revision.txt').read_text().strip(),
        'containers': [item['Name'].removeprefix('/') for item in metadata], 'image_ids': images,
        'architecture': 'linux/amd64', 'files': files,
        'limitations': ['cross-service backups have separate recovery times',
                        'active in-memory game rooms/canvases are not persistent',
                        'Redis is archived for review, not automatically replayed on recovery'],
    }
    (staging / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    final = ROOT / ('capture-' + capture_id)
    staging.rename(final)
    return final, manifest


if __name__ == '__main__':
    try:
        path, manifest = capture()
        print(json.dumps({'capture_path': str(path), 'capture_id': manifest['capture_id'],
                          'bytes': sum(item['size'] for item in manifest['files']), 'complete': True}))
    except Exception as error:
        import traceback
        if ROOT.exists():
            with (ROOT / 'capture-error.private.log').open('a') as log:
                traceback.print_exc(file=log)
        print(json.dumps({'complete': False, 'error_type': type(error).__name__}))
        raise SystemExit(1)
