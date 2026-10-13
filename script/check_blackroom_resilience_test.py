import gzip
import hashlib
import importlib.util
import io
from pathlib import Path
import tarfile
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("resilience", Path(__file__).with_name("check_blackroom_resilience.py"))
resilience = importlib.util.module_from_spec(spec)
spec.loader.exec_module(resilience)


class BackupVerificationTest(unittest.TestCase):
    def test_accepts_dump_and_rejects_tampering_or_missing_dump(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "backup.tar.gz"
            payload = gzip.compress(b"-- isolated backup fixture\n")
            with tarfile.open(path, "w:gz") as archive:
                member = tarfile.TarInfo("dump.sql.gz")
                member.size = len(payload)
                archive.addfile(member, io.BytesIO(payload))
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            self.assertEqual(resilience.verify_backup(path, digest), digest)
            with self.assertRaisesRegex(ValueError, "checksum"):
                resilience.verify_backup(path, "0" * 64)
            with tarfile.open(path, "w:gz"):
                pass
            with self.assertRaisesRegex(ValueError, "dump missing"):
                resilience.verify_backup(path, hashlib.sha256(path.read_bytes()).hexdigest())


if __name__ == "__main__":
    unittest.main()
