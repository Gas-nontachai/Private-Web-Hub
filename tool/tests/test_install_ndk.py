from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from tool.android.install_ndk import flutter_ndk_version, install_ndk

VERSION = '28.2.13676358'
ARCHIVE_ERROR = 'Warning: An error occurred while preparing SDK package NDK (Side by side) 28.2.13676358: Error on ZipFile unknown archive.'


class NdkTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.sdk = Path(self.temp.name)
        self.ndk = self.sdk / 'ndk' / VERSION
        manager = self.sdk / 'cmdline-tools/latest/bin/sdkmanager'
        manager.parent.mkdir(parents=True)
        manager.write_text('fixture')

    def installed(self):
        self.ndk.mkdir(parents=True, exist_ok=True)
        (self.ndk / 'source.properties').write_text(f'Pkg.Revision = {VERSION}\n')
        (self.ndk / 'ndk-build').write_text('fixture')
        compiler = self.ndk / 'toolchains/llvm/prebuilt/linux-x86_64/bin/clang'
        compiler.parent.mkdir(parents=True, exist_ok=True)
        compiler.write_text('fixture')

    @patch('tool.android.install_ndk.time.sleep')
    def test_retries_archive_failure_after_removing_partial_download(self, sleep):
        def run(*args, **kwargs):
            if mock.call_count == 1:
                for name in ('.temp', '.downloadIntermediates', f'ndk/{VERSION}'):
                    path = self.sdk / name
                    path.mkdir(parents=True, exist_ok=True)
                    (path / 'partial.zip').write_text('corrupt download')
                return subprocess.CompletedProcess(args[0], 1, stdout=ARCHIVE_ERROR)
            self.assertFalse((self.sdk / '.temp').exists())
            self.assertFalse((self.sdk / '.downloadIntermediates').exists())
            self.assertFalse(self.ndk.exists())
            self.installed()
            return subprocess.CompletedProcess(args[0], 0, stdout='Installed')
        with patch('tool.android.install_ndk.subprocess.run', side_effect=run) as mock:
            install_ndk(self.sdk, VERSION)
        self.assertEqual(mock.call_count, 2)
        sleep.assert_called_once_with(15)

    def test_skips_a_complete_existing_install(self):
        self.installed()
        with patch('tool.android.install_ndk.subprocess.run') as run:
            install_ndk(self.sdk, VERSION)
        run.assert_not_called()

    def test_non_download_failures_are_not_retried(self):
        with patch('tool.android.install_ndk.subprocess.run', return_value=
                   subprocess.CompletedProcess([], 1, stdout='License not accepted')) as run:
            with self.assertRaises(subprocess.CalledProcessError):
                install_ndk(self.sdk, VERSION)
        self.assertEqual(run.call_count, 1)

    @patch('tool.android.install_ndk.time.sleep')
    def test_stops_after_three_archive_failures(self, sleep):
        other_ndk = self.sdk / 'ndk/other-version'
        other_ndk.mkdir(parents=True)
        with patch('tool.android.install_ndk.subprocess.run', return_value=
                   subprocess.CompletedProcess([], 1, stdout=ARCHIVE_ERROR)) as run:
            with self.assertRaises(subprocess.CalledProcessError):
                install_ndk(self.sdk, VERSION)
        self.assertEqual(run.call_count, 3)
        self.assertEqual([call.args[0] for call in sleep.call_args_list], [15, 30])
        self.assertTrue(other_ndk.exists())

    def test_success_without_usable_files_is_rejected(self):
        self.ndk.mkdir(parents=True)
        (self.ndk / 'source.properties').write_text(f'Pkg.Revision = {VERSION}')
        with patch('tool.android.install_ndk.subprocess.run', return_value=
                   subprocess.CompletedProcess([], 0, stdout='Done')) as run:
            with self.assertRaisesRegex(RuntimeError, 'without a usable NDK'):
                install_ndk(self.sdk, VERSION)
        self.assertEqual(run.call_count, 1)

    def test_reads_version_from_flutter_sdk(self):
        source = self.sdk / 'packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt'
        source.parent.mkdir(parents=True)
        source.write_text(f'val ndkVersion: String = "{VERSION}"')
        self.assertEqual(flutter_ndk_version(self.sdk), VERSION)
        source.write_text('changed Flutter declaration')
        with self.assertRaisesRegex(ValueError, 'Cannot read'):
            flutter_ndk_version(self.sdk)
