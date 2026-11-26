"""生成物の取り違え・破損を検出するテスト。実際の iOS 再生は検証しない。"""

import hashlib
import json
from pathlib import Path
import plistlib
import runpy
import tempfile
import unittest
import zipfile


verify = runpy.run_path(str(Path(__file__).with_name("verify-ipa.py")))["verify"]
SHA = "a" * 40
UPSTREAM = "b" * 40
TREE = "c" * 40


class VerifyIPATest(unittest.TestCase):
    def setUp(self):
        Path("artifacts").mkdir(exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir="artifacts")
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)

    def package(self, *, embedded_sha=SHA, plist_sha=SHA, plist_version="0.1", executable=True, upstream=False, tree=TREE):
        metadata = {"commit_sha": SHA, "version": "0.1", "build_number": "1"}
        if upstream:
            metadata.update(upstream_base_sha=UPSTREAM, app_tree_sha=tree, upstream_app_tree_sha=TREE)
        (self.directory / "build-info.json").write_text(json.dumps(metadata), encoding="utf-8")
        embedded = dict(metadata, commit_sha=embedded_sha)
        plist = {"KonomiTVViewerCommitSHA": plist_sha, "CFBundleShortVersionString": plist_version,
                 "CFBundleVersion": "1", "CFBundleExecutable": "KonomiTV-Viewer"}
        if upstream:
            plist.update(KonomiTVViewerUpstreamBaseSHA=UPSTREAM, KonomiTVViewerAppTreeSHA=tree)
        ipa = self.directory / "test.ipa"
        with zipfile.ZipFile(ipa, "w") as archive:
            root = "Payload/KonomiTV-Viewer.app/"
            archive.writestr(root + "build-info.json", json.dumps(embedded))
            archive.writestr(root + "Info.plist", plistlib.dumps(plist, fmt=plistlib.FMT_BINARY))
            if executable:
                archive.writestr(root + "KonomiTV-Viewer", b"test fixture")
        digest = hashlib.sha256(ipa.read_bytes()).hexdigest()
        (self.directory / "checksums.txt").write_text(f"{digest}  test.ipa\n", encoding="utf-8")
        return ipa

    def test_matching_package(self):
        self.package()
        verify(self.directory, SHA)

    def test_matching_upstream_baseline(self):
        self.package(upstream=True)
        verify(self.directory, SHA, UPSTREAM)

    def test_changed_upstream_tree(self):
        self.package(upstream=True, tree="d" * 40)
        with self.assertRaisesRegex(ValueError, "Upstream application tree mismatch"):
            verify(self.directory, SHA, UPSTREAM)

    def test_wrong_upstream_commit(self):
        self.package(upstream=True)
        with self.assertRaisesRegex(ValueError, "Upstream source commit mismatch"):
            verify(self.directory, SHA, "e" * 40)

    def test_wrong_source_commit(self):
        self.package()
        with self.assertRaisesRegex(ValueError, "source commit mismatch"):
            verify(self.directory, "b" * 40)

    def test_changed_ipa(self):
        ipa = self.package()
        with ipa.open("ab") as stream:
            stream.write(b"changed")
        with self.assertRaisesRegex(ValueError, "SHA-256 mismatch"):
            verify(self.directory, SHA)

    def test_wrong_embedded_metadata(self):
        self.package(embedded_sha="b" * 40)
        with self.assertRaisesRegex(ValueError, "Embedded build metadata mismatch"):
            verify(self.directory, SHA)

    def test_wrong_plist_commit(self):
        self.package(plist_sha="b" * 40)
        with self.assertRaisesRegex(ValueError, "Info.plist source commit mismatch"):
            verify(self.directory, SHA)

    def test_missing_executable(self):
        self.package(executable=False)
        with self.assertRaisesRegex(ValueError, "executable is missing"):
            verify(self.directory, SHA)

    def test_wrong_app_version(self):
        self.package(plist_version="0.2")
        with self.assertRaisesRegex(ValueError, "App version mismatch"):
            verify(self.directory, SHA)

    def test_extra_ipa(self):
        self.package()
        (self.directory / "extra.ipa").write_bytes(b"another build")
        with self.assertRaisesRegex(ValueError, "exactly the IPA"):
            verify(self.directory, SHA)

    def test_checksum_path_escape(self):
        self.package()
        (self.directory / "checksums.txt").write_text("a" * 64 + "  ../test.ipa\n", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "Invalid checksum manifest"):
            verify(self.directory, SHA)


if __name__ == "__main__":
    unittest.main()
