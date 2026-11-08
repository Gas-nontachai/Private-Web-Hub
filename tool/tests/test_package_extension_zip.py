import json
from pathlib import Path
import shutil
import tempfile
import unittest
import zipfile

from tool.release.package_extension_zip import package


class ExtensionZipTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / "extension"
        shutil.copytree(Path(__file__).resolve().parents[2] / "extension", self.source)
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
            self.assertIn('assets/fonts/OFL-Kanit.txt', names)
            for name in names - {'manifest.json'}:
                self.assertEqual(archive.read(name), (self.source / name).read_bytes())
            manifest = json.loads(archive.read("manifest.json"))
            self.assertEqual(manifest["name"], "Movie.exe")
            self.assertEqual(manifest["version"], "1.0.1")
        self.assertEqual((self.source / "manifest.json").read_bytes(), original)

    def test_missing_popup_dependencies_fail(self):
        for name in ('popup/sites.js', 'popup/shared.css', 'assets/fonts/Kanit-Regular.ttf'):
            with self.subTest(name=name):
                path = self.source / name
                content = path.read_bytes()
                path.unlink()
                with self.assertRaisesRegex(ValueError, 'Missing packaged resource'):
                    package(self.source, "v1.0.1", self.output)
                path.write_bytes(content)

    def test_missing_manifest_resource_and_symlinks_fail(self):
        icon = self.source / 'icons/icon32.png'
        icon.unlink()
        with self.assertRaisesRegex(ValueError, 'missing packaged resource'):
            package(self.source, "v1.0.1", self.output)
        icon.symlink_to(self.source / 'icons/icon16.png')
        with self.assertRaisesRegex(ValueError, 'Symlink'):
            package(self.source, "v1.0.1", self.output)

    def test_rejects_signing_material(self):
        (self.source / "secret.pem").write_text("placeholder")
        with self.assertRaisesRegex(ValueError, "Signing material"):
            package(self.source, "v1.0.1", self.output)
        self.assertFalse(self.output.exists())


if __name__ == "__main__":
    unittest.main()
