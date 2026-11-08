import json
from pathlib import Path
import shutil
import tempfile
import unittest

from tool.generate_shared import ROOT, generate, outputs


class SharedTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for name in ('assets', 'extension', 'tool/templates/runtime'):
            shutil.copytree(ROOT / name, self.root / name)
        shutil.copy(ROOT / 'pubspec.yaml', self.root / 'pubspec.yaml')

    def test_current_and_idempotent(self):
        generate(check=True)
        generate(self.root)
        before = {name: (self.root / name).stat().st_mtime_ns for name in outputs(self.root)}
        self.assertEqual(generate(self.root), [])
        self.assertEqual(before, {name: (self.root / name).stat().st_mtime_ns for name in before})

    def test_detects_missing_and_stale_without_writing(self):
        generate(self.root)
        path = self.root / 'extension/assets/fonts/Kanit-Regular.ttf'
        path.unlink()
        css = self.root / 'extension/popup/shared.css'
        css.write_text('stale')
        with self.assertRaisesRegex(ValueError, 'Generated files'):
            generate(self.root, check=True)
        self.assertFalse(path.exists())
        self.assertEqual(css.read_text(), 'stale')

    def test_catalog_tokens_and_font_sources_reach_outputs(self):
        catalog_path = self.root / 'assets/catalog/websites.json'
        catalog = json.loads(catalog_path.read_text())
        site = catalog['sites'][0]
        site.update(name='New name', url='https://new.example/', hosts=['new.example'])
        site['rules'][0].update(hosts=['new.example'])
        site['rules'][0]['actions'][0]['selectors'] = ['.new-ad']
        catalog_path.write_text(json.dumps(catalog))
        token_path = self.root / 'assets/design/design_tokens.json'
        tokens = json.loads(token_path.read_text())
        tokens['colors']['panel'] = '#123456'
        token_path.write_text(json.dumps(tokens))
        font = self.root / 'assets/fonts/Kanit-Regular.ttf'
        font.write_bytes(b'new font fixture')
        data = outputs(self.root)
        self.assertIn(b'New name', data['extension/popup/sites.js'])
        self.assertIn(b'new.example', data['extension/manifest.json'])
        self.assertIn(b'.new-ad', data['extension/rules/serieday.css'])
        for name in ('extension/popup/shared.css', 'pubspec.yaml', 'android/app/src/main/res/values/colors.xml'):
            self.assertIn(b'#123456', data[name])
        self.assertIn(b'0xFF123456', data['lib/src/theme/design_tokens.dart'])
        self.assertEqual(data['extension/assets/fonts/Kanit-Regular.ttf'], b'new font fixture')
        self.assertEqual(data['extension/assets/fonts/OFL-Kanit.txt'], (self.root / 'assets/fonts/OFL-Kanit.txt').read_bytes())

    def test_narrow_rule_scope_is_rejected(self):
        path = self.root / 'assets/catalog/websites.json'
        catalog = json.loads(path.read_text())
        catalog['sites'][0]['rules'][0]['parentHosts'] = ['parent.example']
        path.write_text(json.dumps(catalog))
        with self.assertRaisesRegex(ValueError, 'rule hosts'):
            outputs(self.root)
