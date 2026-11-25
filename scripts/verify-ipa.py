"""IPA と同梱情報を照合する。CI とダウンロード後の確認に同じ手順を使う。"""

import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import zipfile


def verify(directory: Path, expected_sha: str) -> None:
    # checksum のファイル名は単一の IPA 名だけを受け付け、ディレクトリ外を参照しない。
    checksum = (directory / "checksums.txt").read_text(encoding="utf-8").strip()
    match = re.fullmatch(r"([0-9a-f]{64})  ([A-Za-z0-9._-]+\.ipa)", checksum)
    if not match:
        raise ValueError("Invalid checksum manifest")
    digest, filename = match.groups()
    ipa = directory / filename
    if sorted(directory.glob("*.ipa")) != [ipa]:
        raise ValueError("Expected exactly the IPA named in checksums.txt")
    with ipa.open("rb") as stream:
        if hashlib.file_digest(stream, "sha256").hexdigest() != digest:
            raise ValueError("IPA SHA-256 mismatch")

    metadata = json.loads((directory / "build-info.json").read_text(encoding="utf-8"))
    if not re.fullmatch(r"[0-9a-f]{40}", expected_sha):
        raise ValueError("Expected a full source commit SHA")
    if metadata["commit_sha"] != expected_sha:
        raise ValueError("Artifact source commit mismatch")
    with zipfile.ZipFile(ipa) as archive:
        # 展開せず、アプリ内の来歴と Info.plist を検査する。
        corrupt = archive.testzip()
        if corrupt:
            raise ValueError(f"Corrupt ZIP entry: {corrupt}")
        root = "Payload/KonomiTV-Viewer.app/"
        embedded = json.loads(archive.read(root + "build-info.json"))
        plist = plistlib.loads(archive.read(root + "Info.plist"))
        if embedded != metadata:
            raise ValueError("Embedded build metadata mismatch")
        if plist.get("KonomiTVViewerCommitSHA") != expected_sha:
            raise ValueError("Info.plist source commit mismatch")
        if plist["CFBundleShortVersionString"] != metadata["version"]:
            raise ValueError("App version mismatch")
        if plist["CFBundleVersion"] != metadata["build_number"]:
            raise ValueError("App build number mismatch")
        if root + plist["CFBundleExecutable"] not in archive.namelist():
            raise ValueError("App executable is missing")
    print(f"Verified {filename}: commit={expected_sha}, sha256={digest}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--expected-sha", required=True)
    args = parser.parse_args()
    verify(args.directory, args.expected_sha)
