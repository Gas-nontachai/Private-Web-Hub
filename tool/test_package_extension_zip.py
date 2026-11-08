import json
from pathlib import Path
import shutil
import tempfile
import unittest
import zipfile

from package_extension_zip import package


class ExtensionZipTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / "extension"
        shutil.copytree(Path(__file__).resolve().parents[1] / "extension", self.source)
        self.output = self.root / "Movie.exe-v1.0.1.zip"

    def test_load_unpacked_layout_and_version(self):
        original = (self.source / "manifest.json").read_bytes()
        package(self.source, "v1.0.1", self.output)
        with zipfile.ZipFile(self.output) as archive:
            names = set(archive.namelist())
            self.assertIn("manifest.json", names)
            self.assertIn("popup/index.html", names)
            self.assertFalse(any(name.startswith("extension/") for name in names))
            self.assertIsNone(archive.testzip())
            manifest = json.loads(archive.read("manifest.json"))
            self.assertEqual(manifest["name"], "Movie.exe")
            self.assertEqual(manifest["version"], "1.0.1")
        self.assertEqual((self.source / "manifest.json").read_bytes(), original)

    def test_rejects_signing_material(self):
        (self.source / "secret.pem").write_text("placeholder")
        with self.assertRaisesRegex(ValueError, "Signing material"):
            package(self.source, "v1.0.1", self.output)
        self.assertFalse(self.output.exists())


if __name__ == "__main__":
    unittest.main()
