import hashlib
from pathlib import Path
import tempfile
import unittest
import zipfile

from tool.release.verify_release_apk import validate


class VerifyReleaseApkTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.apk = self.root / 'app.apk'
        self.cert = self.root / 'cert.der'
        self.cert.write_bytes(b'test certificate')
        self.signing = self.root / 'signing.txt'
        self.signing.write_text('Signer #1 certificate SHA-256 digest: ' + hashlib.sha256(self.cert.read_bytes()).hexdigest())
        self.badging = self.root / 'badging.txt'
        self.metadata = """package: name='com.nonthachai.privatewebhub' versionCode='1001003' versionName='1.1.3'
application-label:'Movie.exe'
application: label='Movie.exe' icon='icon.png' banner='banner.xml'
leanback-launchable-activity: 'com.nonthachai.privatewebhub.MainActivity'
uses-feature-not-required: name='android.hardware.touchscreen'
"""
        self.badging.write_text(self.metadata)

    def check_target(self, target):
        validate(self.apk, self.cert, self.signing, self.badging, '1.1.3', '1001003', target)

    def apk_with(self, abis):
        with zipfile.ZipFile(self.apk, 'w') as archive:
            for abi in abis:
                archive.writestr(f'lib/{abi}/libflutter.so', b'fake library')

    def test_tv_accepts_both_arm_abis_without_x86(self):
        self.apk_with(['armeabi-v7a', 'arm64-v8a'])
        self.check_target('tv')
        with self.assertRaisesRegex(ValueError, 'x86_64'):
            self.check_target('universal')

    def test_tv_requires_32_bit_arm_and_launcher_and_optional_touch(self):
        self.apk_with(['arm64-v8a'])
        with self.assertRaisesRegex(ValueError, 'armeabi-v7a'):
            self.check_target('tv')
        self.apk_with(['armeabi-v7a', 'arm64-v8a'])
        for metadata in [self.metadata.replace('leanback-launchable-activity', 'launcher'),
                         self.metadata.replace('banner=', 'missing='),
                         self.metadata.replace('uses-feature-not-required', 'uses-feature')]:
            self.badging.write_text(metadata)
            with self.assertRaises(ValueError):
                self.check_target('tv')

    def test_rejects_wrong_signature_and_debug_package(self):
        self.apk_with(['armeabi-v7a', 'arm64-v8a', 'x86_64'])
        self.check_target('universal')
        self.badging.write_text(self.metadata.replace("privatewebhub'", "privatewebhub.tvpreview'"))
        with self.assertRaisesRegex(ValueError, 'applicationId'):
            self.check_target('tv')
        self.cert.write_bytes(b'another certificate')
        with self.assertRaisesRegex(ValueError, 'certificate mismatch'):
            self.check_target('tv')
