#!/usr/bin/env python3
"""Losslessly compress a completed recovery set; retain the original and never upload."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile

from capture import ROOT, digest

ARCHIVES = {'images.tar', 'forum-models.tar', 'deployment-and-services.tar', 'forum-state.tar'}


def model_config(source, staging):
    weights = {}
    with tarfile.open(source / 'forum-models.tar') as archive:
        for member in archive:
            if member.isfile() and '/manifests/' in member.name:
                data = json.load(archive.extractfile(member))
                for layer in data['layers']:
                    if layer['mediaType'] == 'application/vnd.ollama.image.model':
                        sha = layer['digest'].split(':', 1)[1]
                        if '/hf.co/' in member.name:
                            url = 'https://huggingface.co/tencent/HY-MT1.5-1.8B-GGUF/resolve/265b2e615a7dc9b06c435dc878829ad99a512ba2/HY-MT1.5-1.8B-Q4_K_M.gguf'
                        else:
                            model = layer['from'].split(':', 1)[0]
                            url = f'https://registry.ollama.ai/v2/library/{model}/blobs/sha256:{sha}'
                        weights['sha256-' + sha] = {'sha256': sha, 'size': layer['size'], 'url': url}
        target = staging / 'forum-model-config.tar'
        with tarfile.open(target, 'w') as output:
            for member in archive.getmembers():
                if Path(member.name).name in weights:
                    continue
                output.addfile(member, archive.extractfile(member) if member.isfile() else None)
    plan = staging / 'models-download.json'
    plan.write_text(json.dumps({'weights': list(weights.values()), 'excluded_weight_bytes': sum(x['size'] for x in weights.values())}, indent=2) + '\n')
    return target, plan


def compact(source):
    if source.parent != ROOT or not source.name.startswith('capture-') or source.name.endswith('.partial'):
        raise ValueError('A completed local recovery set is required')
    original = json.loads((source / 'manifest.json').read_text())
    destination = source.with_name(source.name + '-lean')
    staging = destination.with_name(destination.name + '.partial')
    if destination.exists() or staging.exists():
        raise ValueError('Existing recovery material is preserved')
    os.umask(0o077)
    staging.mkdir()
    files = []
    for item in original['files']:
        name = item['path']
        if not name or Path(name).name != name or name in {'.', '..'}:
            raise ValueError('Unsafe manifest path')
        path = source / name
        if path.is_symlink() or not path.is_file() or path.stat().st_size != item['size']:
            raise ValueError('Source recovery file missing or wrong size')
        if name == 'forum-models.tar':
            path, plan = model_config(source, staging)
            name = path.name
            item = {'path': name, 'size': path.stat().st_size, 'sha256': digest(path)}
            files.append({'path': plan.name, 'size': plan.stat().st_size, 'sha256': digest(plan)})
        if name in ARCHIVES or name == 'forum-model-config.tar':
            target = staging / (name + '.zst')
            subprocess.run(['zstd', '-q', '-T2', '-3', str(path), '-o', str(target)], check=True)
            sha = hashlib.sha256()
            with subprocess.Popen(['zstd', '-q', '-dc', str(target)], stdout=subprocess.PIPE) as process:
                for chunk in iter(lambda: process.stdout.read(1024 * 1024), b''):
                    sha.update(chunk)
                if process.wait() or sha.hexdigest() != item['sha256']:
                    raise ValueError('Compressed archive does not reproduce the original')
            files.append({'path': target.name, 'size': target.stat().st_size, 'sha256': digest(target),
                          'uncompressed_path': name, 'uncompressed_size': item['size'],
                          'uncompressed_sha256': item['sha256']})
            if name == 'forum-model-config.tar':
                path.unlink()
        else:
            if digest(path) != item['sha256']:
                raise ValueError('Source checksum mismatch')
            target = staging / name
            os.link(path, target)
            files.append(item)
    manifest = {**original, 'variant': 'zstd-models-redownload', 'files': files}
    (staging / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    staging.rename(destination)
    return {'capture_path': str(destination), 'original_bytes': sum(x['size'] for x in original['files']),
            'compact_bytes': sum(x['size'] for x in files), 'lossless_verified': True,
            'files': [{'name': x['path'], 'bytes': x['size']} for x in files]}


if __name__ == '__main__':
    print(json.dumps(compact(Path(sys.argv[1]))))
