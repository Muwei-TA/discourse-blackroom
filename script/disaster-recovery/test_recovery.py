import hashlib
import json
from pathlib import Path
import tempfile
import shutil
import tarfile
import io
import unittest
from unittest.mock import patch

from configure_r2 import read_s3_key
from restore import verify, unpack
from compact import compact, model_config
from download_models import download


class RecoveryTests(unittest.TestCase):
    def test_s3_key_retries_api_token_then_accepts_key(self):
        with patch('configure_r2.getpass.getpass', side_effect=['api-token', 'a' * 64]), patch('builtins.print') as output:
            self.assertEqual(read_s3_key('hidden', 64), 'a' * 64)
            self.assertEqual(output.call_count, 1)

    def test_manifest_rejects_corruption_traversal_and_symlink(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'data').write_bytes(b'backup')
            item = {'path': 'data', 'size': 6, 'sha256': hashlib.sha256(b'backup').hexdigest()}
            manifest = root / 'manifest.json'
            manifest.write_text(json.dumps({'files': [item]}))
            verify(root)
            (root / 'data').write_bytes(b'broken')
            with self.assertRaises(ValueError):
                verify(root)
            for name in ['../data', '.', '..', '/data']:
                manifest.write_text(json.dumps({'files': [{**item, 'path': name}]}))
                with self.assertRaises(ValueError):
                    verify(root)
            (root / 'data').unlink()
            (root / 'data').symlink_to(manifest)
            manifest.write_text(json.dumps({'files': [item]}))
            with self.assertRaises(ValueError):
                verify(root)

    @unittest.skipUnless(shutil.which('zstd'), 'zstd unavailable')
    def test_lossless_compaction_roundtrip_and_existing_destination_preserved(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / 'capture-test'
            source.mkdir()
            data = b'complete program archive' * 1000
            (source / 'images.tar').write_bytes(data)
            item = {'path': 'images.tar', 'size': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
            (source / 'manifest.json').write_text(json.dumps({'capture_id': 'test', 'files': [item]}))
            with patch('compact.ROOT', root):
                result = compact(source)
                with self.assertRaises(ValueError):
                    compact(source)
            destination = Path(result['capture_path'])
            manifest = verify(destination)
            self.assertLess(result['compact_bytes'], result['original_bytes'])
            unpack(destination, manifest)
            self.assertEqual((destination / 'images.tar').read_bytes(), data)
            self.assertEqual((source / 'images.tar').read_bytes(), data)
            with self.assertRaises(ValueError):
                unpack(destination, manifest)


    def test_model_weights_omitted_but_custom_configuration_retained(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            staging = root / 'staging'
            staging.mkdir()
            sha = 'a' * 64
            manifest = json.dumps({'layers': [{'mediaType': 'application/vnd.ollama.image.model',
                'digest': 'sha256:' + sha, 'size': 6, 'from': 'qwen2.5:7b-instruct'}]}).encode()
            with tarfile.open(root / 'forum-models.tar', 'w') as archive:
                for name, data in [('models/manifests/registry.ollama.ai/library/blackroom-moderator/latest', manifest),
                    ('models/blobs/sha256-' + sha, b'weight'), ('models/blobs/sha256-custom', b'custom configuration')]:
                    member = tarfile.TarInfo(name)
                    member.size = len(data)
                    archive.addfile(member, io.BytesIO(data))
            config, plan = model_config(root, staging)
            with tarfile.open(config) as archive:
                names = archive.getnames()
            self.assertNotIn('models/blobs/sha256-' + sha, names)
            self.assertIn('models/blobs/sha256-custom', names)
            self.assertEqual(json.loads(plan.read_text())['excluded_weight_bytes'], 6)


    def test_model_download_verifies_bytes_and_rejects_other_sources(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            data = b'model'
            sha = hashlib.sha256(data).hexdigest()
            item = {'sha256': sha, 'size': len(data), 'url': 'https://registry.ollama.ai/blob'}
            plan = root / 'plan.json'
            plan.write_text(json.dumps({'weights': [item]}))
            with patch('download_models.urllib.request.urlopen', return_value=io.BytesIO(data)), patch('builtins.print'):
                download(plan, root / 'blobs')
            self.assertEqual((root / 'blobs' / ('sha256-' + sha)).read_bytes(), data)
            plan.write_text(json.dumps({'weights': [{**item, 'url': 'http://localhost/secret'}]}))
            with patch('download_models.urllib.request.urlopen') as request:
                with self.assertRaises(ValueError):
                    download(plan, root / 'other')
                request.assert_not_called()



if __name__ == '__main__':
    unittest.main()
