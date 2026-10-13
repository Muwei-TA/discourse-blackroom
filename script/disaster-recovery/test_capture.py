"""Local-only checks for recovery capture boundaries; never invokes Docker."""
import gzip
import hashlib
import importlib.util
import io
import shutil
import subprocess
import tarfile
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("blackroom_dr_capture", Path(__file__).with_name("capture.py"))
capture = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(capture)


class CaptureTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)

    def backup(self, members=None):
        path = self.root / "forum.tar.gz"
        if members is None:
            members = [
                ("dump.sql.gz", gzip.compress(b"-- Synthetic SQL dump\nSELECT 1;\n")),
                ("uploads/default/original/1X/image.png", b"synthetic upload"),
            ]
        with tarfile.open(path, "w:gz") as archive:
            for name, data in members:
                if isinstance(name, tarfile.TarInfo):
                    info = name
                else:
                    info = tarfile.TarInfo(name)
                    info.size = len(data)
                archive.addfile(info, io.BytesIO(data))
        return path

    def reject_backup(self, path):
        with self.assertRaises((ValueError, tarfile.TarError, EOFError, OSError)):
            capture.verify_forum_backup(path)

    def test_sha256_empty_and_multiple_chunks(self):
        path = self.root / "data"
        for data in (b"", b"BlackRoom\n", bytes(range(256)) * 8193):
            with self.subTest(size=len(data)):
                path.write_bytes(data)
                self.assertEqual(capture.digest(path), hashlib.sha256(data).hexdigest())

    def test_complete_forum_backup_counts_regular_uploads(self):
        self.assertEqual(capture.verify_forum_backup(self.backup()), 1)

    def test_missing_dump_or_uploads_is_rejected(self):
        for members in (
            [("uploads/default/original/image.png", b"image")],
            [("dump.sql.gz", gzip.compress(b"SELECT 1;"))],
            [("dump.sql.gz", b""), ("uploads/default/original/image.png", b"image")],
        ):
            with self.subTest(members=[name for name, _ in members]):
                self.reject_backup(self.backup(members))

    def test_empty_upload_does_not_prove_file_recovery(self):
        self.reject_backup(self.backup([
            ("dump.sql.gz", gzip.compress(b"SELECT 1;")),
            ("uploads/default/original/image.png", b""),
        ]))

    def test_corrupt_or_truncated_inner_dump_is_rejected(self):
        for dump in (b"not gzip", gzip.compress(b"SELECT 1;" )[:-5]):
            with self.subTest(dump=dump[:8]):
                self.reject_backup(self.backup([
                    ("dump.sql.gz", dump),
                    ("uploads/default/original/image.png", b"image"),
                ]))

    def test_noncanonical_dump_name_is_rejected(self):
        self.reject_backup(self.backup([
            ("unrelated/not-a-dump.sql.gz", gzip.compress(b"SELECT 1;")),
            ("uploads/default/original/image.png", b"image"),
        ]))

    def test_truncated_outer_archive_is_rejected(self):
        path = self.backup()
        data = path.read_bytes()
        for content in (data[:len(data) // 2], data[:-8]):
            with self.subTest(length=len(content)):
                path.write_bytes(content)
                self.reject_backup(path)

    def test_traversal_and_absolute_member_names_are_rejected(self):
        for name in ("uploads/../../escaped", "/tmp/escaped", "../escaped"):
            with self.subTest(name=name):
                self.reject_backup(self.backup([
                    ("dump.sql.gz", gzip.compress(b"SELECT 1;")),
                    ("uploads/default/original/image.png", b"image"),
                    (name, b"outside"),
                ]))

    def test_symlinks_and_hardlinks_are_rejected(self):
        for kind in (tarfile.SYMTYPE, tarfile.LNKTYPE):
            with self.subTest(kind=kind):
                info = tarfile.TarInfo("uploads/default/original/link.png")
                info.type = kind
                info.linkname = "/etc/passwd"
                self.reject_backup(self.backup([
                    ("dump.sql.gz", gzip.compress(b"SELECT 1;")),
                    ("uploads/default/original/image.png", b"image"),
                    (info, b""),
                ]))

    def test_dump_must_be_regular_file(self):
        directory = tarfile.TarInfo("dump.sql.gz")
        directory.type = tarfile.DIRTYPE
        directory.size = 1
        self.reject_backup(self.backup([
            (directory, b"x"),
            ("uploads/default/original/image.png", b"image"),
        ]))

    @unittest.skipUnless(shutil.which("tar"), "system tar unavailable")
    def test_archive_keeps_private_env_and_state_but_excludes_live_db_and_caches(self):
        source = self.root / "deployment"
        kept = (
            "private/gateway.json", ".env", "source/private/.env", "state/publisher.rb",
            "state/blackroom-updates.disabled", "containers/app.yml", "compose.yaml",
        )
        excluded = (
            ".git/config", "node_modules/pkg/index.js", "__pycache__/mod.pyc", "capture.log",
            "backup.part", "._metadata", "resilience/old.tar", "postgres_data/PG_VERSION",
            "redis_data/dump.rdb", "shared/postgres_data/base", "config.db", "config.db-wal",
            "config.db-shm",
        )
        for name in kept + excluded:
            path = source / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"fixture")
        output = self.root / "deployment.tar"

        def local_tar(args, target=None):
            self.assertEqual(args[0], "tar")
            with target.open("wb") as stream:
                subprocess.run(args, stdout=stream, stderr=subprocess.PIPE, check=True)

        with patch.object(capture, "command", side_effect=local_tar):
            capture.archive(output, [source])
        with tarfile.open(output) as archive:
            names = [member.name for member in archive if member.isfile()]
        for name in kept:
            self.assertTrue(any(item.endswith("/deployment/" + name) for item in names), name)
        for name in excluded:
            self.assertFalse(any(item.endswith("/deployment/" + name) for item in names), name)

    def test_archive_missing_source_fails_before_command(self):
        with patch.object(capture, "command") as command:
            with self.assertRaises(ValueError):
                capture.archive(self.root / "out.tar", [self.root / "missing"])
            command.assert_not_called()

    def test_wrong_host_and_unmounted_volume_stop_before_writes(self):
        deploy = self.root / "deployment"
        shared = self.root / "shared"
        destination = self.root / "not-created"
        with patch.object(capture, "DEPLOY", deploy), patch.object(capture, "SHARED", shared), \
             patch.object(capture, "ROOT", destination), patch.object(capture, "command") as command, \
             patch.object(capture.subprocess, "check_output") as docker:
            with self.assertRaisesRegex(ValueError, "intended NAS"):
                capture.capture()
            (deploy / "containers").mkdir(parents=True)
            (deploy / "containers/app.yml").write_text("fixture")
            shared.mkdir()
            with patch.object(capture.os.path, "ismount", return_value=False):
                with self.assertRaisesRegex(ValueError, "must be mounted"):
                    capture.capture()
            command.assert_not_called()
            docker.assert_not_called()
            self.assertFalse(destination.exists())


if __name__ == "__main__":
    unittest.main()
