import base64
import contextlib
import io
import json
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import unittest
import zipfile

from release_extension import android_build_number, chrome_version, fields, pack, release_version, verify


class ReleaseVersionTests(unittest.TestCase):
    def test_release_version(self):
        self.assertEqual(release_version("v0.2.0"), "0.2.0")
        self.assertEqual(release_version("v65535.0.1"), "65535.0.1")

    def test_invalid_tags(self):
        for tag in (
            "0.2.0", "v0.0.0", "v65536.0.1", "v01.2.3", "v1.2", "v1.2.3.4",
            "v1.2.3-beta", "v1.2.3+build", "v1.2.3\n", "$(echo v1.2.3)",
        ):
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                release_version(tag)

    def test_android_build_number_from_tag(self):
        self.assertEqual(android_build_number("v1.2.3"), 1002003)
        self.assertEqual(android_build_number("v1.0.0"), 1000000)
        self.assertEqual(android_build_number("v1.0.1"), 1000001)
        self.assertEqual(android_build_number("v0.0.1"), 1)
        self.assertEqual(android_build_number("v2099.999.999"), 2099999999)

    def test_invalid_android_build_numbers(self):
        for tag in ("v1.1000.0", "v1.0.1000", "v2101.0.0"):
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                android_build_number(tag)

    def test_source_manifest_version(self):
        for version in ("1", "1.0", "1.0.0", "1.2.3.4", "0.0.0.1"):
            chrome_version(version)
        for version in ("0", "0.0.0.0", "1.02", "1.2.3.4.5", "65536", "1-beta", 1):
            with self.subTest(version=version), self.assertRaises(ValueError):
                chrome_version(version)


class CrxTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory()
        cls.key = Path(cls.temporary.name, "test-only.pem")
        # Disposable test fixture, never used by the release pack command.
        subprocess.run(
            ["openssl", "genpkey", "-algorithm", "RSA", "-pkeyopt", "rsa_keygen_bits:2048",
             "-out", str(cls.key)],
            check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def setUp(self):
        self.working = tempfile.TemporaryDirectory()
        self.addCleanup(self.working.cleanup)
        self.root = Path(self.working.name)
        self.source = self.root / "extension"
        shutil.copytree(Path(__file__).resolve().parents[1] / "extension", self.source)
        self.output = self.root / "Movie.exe-v0.2.0.crx"
        self.manifest_path = self.source / "manifest.json"
        self.manifest = json.loads(self.manifest_path.read_text())

    def write_manifest(self):
        self.manifest_path.write_text(json.dumps(self.manifest))

    def package(self, tag="v0.2.0"):
        with contextlib.redirect_stdout(io.StringIO()):
            pack(self.source, tag, self.key, self.output)

    def archive(self):
        data = self.output.read_bytes()
        header_size = struct.unpack("<I", data[8:12])[0]
        return zipfile.ZipFile(io.BytesIO(data[12 + header_size:]))

    def test_package_preserves_runtime_and_contains_no_secrets(self):
        git = self.source / ".git"
        git.mkdir()
        (git / "config").write_text("test checkout credentials")
        original_manifest = self.manifest_path.read_bytes()
        self.package()
        with self.archive() as archive:
            manifest = json.loads(archive.read("manifest.json"))
            self.assertEqual(manifest["name"], "Movie.exe")
            self.assertEqual(manifest["version"], "0.2.0")
            original = dict(self.manifest, name="Movie.exe", version="0.2.0")
            self.assertEqual(manifest, original)
            self.assertFalse(any(name.startswith(".git/") for name in archive.namelist()))
            for name in archive.namelist():
                if name != "manifest.json":
                    self.assertEqual(archive.read(name), (self.source / name).read_bytes())
        self.assertEqual(original_manifest, self.manifest_path.read_bytes())
        self.assertEqual(list(self.root.glob("*.zip")), [])
        self.assertEqual(list(self.root.glob("*.pem")), [])

    def test_same_key_retains_id_across_versions(self):
        self.package()
        with contextlib.redirect_stdout(io.StringIO()):
            first_id = verify(self.output, "v0.2.0")
            self.package("v1.0.0")
            second_id = verify(self.output, "v1.0.0")
        self.assertEqual(first_id, second_id)
        self.assertRegex(first_id, r"^[a-p]{32}$")

    def test_existing_manifest_key_must_match(self):
        self.manifest["key"] = base64.b64encode(b"not the signing key").decode()
        self.write_manifest()
        with self.assertRaisesRegex(ValueError, "does not match"):
            self.package()
        self.manifest["key"] = base64.b64encode(subprocess.check_output(
            ["openssl", "pkey", "-in", str(self.key), "-pubout", "-outform", "DER"]
        )).decode()
        self.write_manifest()
        self.package()

    def test_invalid_source_manifest_and_missing_resources_fail(self):
        self.manifest["version"] = "1.0-beta"
        self.write_manifest()
        with self.assertRaisesRegex(ValueError, "manifest version"):
            self.package()
        self.manifest["version"] = "1.0.0"
        self.manifest["action"]["default_popup"] = "missing.html"
        self.write_manifest()
        with self.assertRaisesRegex(ValueError, "missing packaged resource"):
            self.package()

    def test_signing_material_in_source_is_rejected(self):
        (self.source / "accidental.pem").write_text("test-only placeholder")
        with self.assertRaisesRegex(ValueError, "signing material"):
            self.package()

    def test_wrong_release_version_is_rejected(self):
        self.package()
        with self.assertRaisesRegex(ValueError, "does not match"):
            verify(self.output, "v0.3.0")

    def test_tampered_payload_fails_signature_verification(self):
        self.package()
        data = bytearray(self.output.read_bytes())
        data[-1] ^= 1
        self.output.write_bytes(data)
        with self.assertRaises(subprocess.CalledProcessError):
            verify(self.output, "v0.2.0")

    def test_wrong_identity_is_rejected(self):
        self.package()
        with self.assertRaisesRegex(ValueError, "identity does not match"):
            verify(self.output, "v0.2.0", expected_key=b"different public key")

    def test_truncated_header_and_duplicate_fields_are_rejected(self):
        self.output.write_bytes(b"Cr24" + struct.pack("<II", 3, 100))
        with self.assertRaisesRegex(ValueError, "header"):
            verify(self.output, "v0.2.0")
        for data in (b"\x12\x02x", b"\x12\x01x\x12\x01y", b"\x80", b"\x08\x00"):
            with self.subTest(data=data), self.assertRaises(ValueError):
                fields(data)


if __name__ == "__main__":
    unittest.main()
