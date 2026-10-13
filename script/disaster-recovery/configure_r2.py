#!/usr/bin/env python3
"""Run interactively on the NAS; secrets are never printed or passed as CLI arguments."""
import getpass
import json
import os
import re
import sys
from pathlib import Path

ROOT = Path('/vol4/1000/backup/blackroom/offsite/private')
ACCOUNT = '841556b7f158ae0bc937a144cefbcb3b'
BUCKET = 'blackroom-disaster-recovery'


def read_s3_key(prompt, length):
    while True:
        value = getpass.getpass(prompt).strip()
        if re.fullmatch(r"[0-9a-fA-F]{%d}" % length, value):
            return value
        print(f"Expected {length} hexadecimal characters from the R2 S3 credential screen; do not use the API token value.")


def main():
    if not Path('/home/muwei/discourse-docker-preview/containers/app.yml').exists():
        raise SystemExit('Run this helper on the intended NAS.')
    os.umask(0o077)
    ROOT.mkdir(parents=True, exist_ok=True)
    config = ROOT / 'r2.json'
    password = ROOT / 'restic-password'
    replace_keys = sys.argv[1:] == ['--replace-s3-keys']
    if sys.argv[1:] and not replace_keys:
        raise SystemExit('Only --replace-s3-keys is supported.')
    if replace_keys:
        if not config.is_file() or not password.is_file() or config.stat().st_mode & 0o077:
            raise SystemExit('Protected existing configuration required; nothing changed.')
        existing = json.loads(config.read_text())
    elif config.exists() or password.exists():
        raise SystemExit('Existing credentials preserved; use --replace-s3-keys to fix S3 credentials only.')
    print('Use a bucket-scoped R2 S3 credential: Object Read & Write, only blackroom-disaster-recovery.')
    access = read_s3_key('R2 Access Key ID, 32 hexadecimal characters (hidden): ', 32)
    secret = read_s3_key('R2 Secret Access Key, 64 hexadecimal characters (hidden): ', 64)
    if replace_keys:
        existing.update(access_key_id=access, secret_access_key=secret)
        temporary = config.with_suffix('.part')
        temporary.write_text(json.dumps(existing))
        temporary.chmod(0o600)
        temporary.replace(config)
        print('Protected S3 credentials updated. Existing recovery passphrase preserved. No credentials printed.')
        return
    while True:
        phrase = getpass.getpass('Restic recovery passphrase, at least 20 characters (hidden): ')
        if len(phrase) < 20:
            print('Recovery passphrase is shorter than 20 characters. Only re-enter the passphrase.')
            continue
        if any(c in phrase for c in '\r\n\0'):
            print('Recovery passphrase must be a single line. Only re-enter the passphrase.')
            continue
        repeated = getpass.getpass('Repeat the same recovery passphrase (hidden): ')
        if phrase != repeated:
            print('The two recovery passphrases differ. Only re-enter the passphrase.')
            continue
        break
    if any(c in access + secret for c in '\r\n\0'):
        raise SystemExit('S3 credentials must be a single line; nothing saved.')
    while True:
        answer = input('是否已在 NAS 之外保存恢复口令？输入 yes 或 是：').strip().casefold()
        if answer in {'yes', '是'}:
            break
        if answer in {'no', '否'}:
            raise SystemExit('请先把口令保存到 NAS 之外；目前未保存配置。')
        print('请输入 yes 或 是确认；前面的隐藏输入仍保留，无需重填。')
    password.write_text(phrase + '\n')
    password.chmod(0o600)
    config.write_text(json.dumps({
        'repository': f's3:https://{ACCOUNT}.r2.cloudflarestorage.com/{BUCKET}/restic',
        'access_key_id': access, 'secret_access_key': secret,
        'password_file': str(password), 'key_escrow_confirmed': True,
    }))
    config.chmod(0o600)
    print('Protected configuration saved. No credentials printed. Keep the independent passphrase copy.')


if __name__ == '__main__':
    main()
