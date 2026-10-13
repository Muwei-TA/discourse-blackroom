#!/usr/bin/env python3
"""Restore omitted AI weights from pinned upstream content; do not start Ollama."""
import hashlib
import json
import os
from pathlib import Path
import sys
import urllib.parse
import urllib.request


def download(plan, destination):
    os.umask(0o077)
    destination.mkdir(parents=True, exist_ok=True)
    for item in json.loads(plan.read_text())['weights']:
        sha = item['sha256']
        if len(sha) != 64 or any(c not in '0123456789abcdef' for c in sha):
            raise ValueError('Invalid model digest')
        url = urllib.parse.urlparse(item['url'])
        if url.scheme != 'https' or url.hostname not in {'registry.ollama.ai', 'huggingface.co'} or url.username:
            raise ValueError('Unexpected model source')
        target = destination / ('sha256-' + sha)
        temporary = target.with_suffix('.part')
        if target.exists() or target.is_symlink() or temporary.exists() or temporary.is_symlink():
            raise ValueError('Existing model files are preserved')
        digest = hashlib.sha256()
        count = 0
        with urllib.request.urlopen(item['url'], timeout=60) as response, temporary.open('xb') as stream:
            while chunk := response.read(1024 * 1024):
                count += len(chunk)
                if count > item['size']:
                    raise ValueError('Model exceeds expected size')
                digest.update(chunk)
                stream.write(chunk)
        if count != item['size'] or digest.hexdigest() != sha:
            raise ValueError('Downloaded model checksum mismatch; partial file retained')
        temporary.rename(target)
    print(json.dumps({'model_weights_downloaded_and_verified': True, 'ollama_started': False}))


if __name__ == '__main__':
    download(Path(sys.argv[1]), Path(sys.argv[2]))
