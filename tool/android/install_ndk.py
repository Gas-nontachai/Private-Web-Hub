"""Install Flutter's required NDK before CI enters Gradle configuration."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import time


def flutter_ndk_version(flutter_root):
    source = Path(flutter_root) / 'packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt'
    match = re.search(r'val ndkVersion: String = "([0-9]+\.[0-9]+\.[0-9]+)"', source.read_text())
    if not match:
        raise ValueError('Cannot read the pinned Flutter SDK NDK version')
    return match[1]


def ndk_installed(ndk, version):
    properties = ndk / 'source.properties'
    if not properties.is_file():
        return False
    match = re.search(r'^Pkg\.Revision\s*=\s*(\S+)\s*$', properties.read_text(), re.M)
    return (match is not None and match[1] == version
            and (ndk / 'ndk-build').is_file()
            and any(path.is_file() for path in (ndk / 'toolchains/llvm/prebuilt').glob('*/bin/clang')))


def install_ndk(sdk_root, version):
    if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', version):
        raise ValueError('Invalid NDK version')
    sdk_root = Path(sdk_root).resolve()
    manager = sdk_root / 'cmdline-tools/latest/bin/sdkmanager'
    if not manager.is_file():
        raise FileNotFoundError(f'Missing SDK manager: {manager}')
    ndk = sdk_root / 'ndk' / version
    if ndk_installed(ndk, version):
        print(f'NDK {version} is already installed', flush=True)
        return
    command = [str(manager), f'--sdk_root={sdk_root}', '--install', f'ndk;{version}', '--verbose']
    for attempt in range(1, 4):
        print(f'Installing NDK {version} (attempt {attempt}/3)', flush=True)
        result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        output = result.stdout or ''
        print(output, flush=True)
        if result.returncode == 0:
            if not ndk_installed(ndk, version):
                raise RuntimeError(f'sdkmanager completed without a usable NDK {version}')
            return
        retryable = re.search(
            r'ZipFile|Not in GZIP format|zip END header|Unexpected end of|'
            r'Connection reset|timed out|HTTP (?:429|5[0-9]{2})', output, re.I,
        )
        if not retryable or attempt == 3:
            raise subprocess.CalledProcessError(result.returncode, command)
        # CI installs SDK packages serially; discard only SDK download staging and this partial NDK.
        for path in (sdk_root / '.temp', sdk_root / '.downloadIntermediates'):
            if path.exists():
                shutil.rmtree(path)
        if ndk.exists() and not ndk_installed(ndk, version):
            shutil.rmtree(ndk)
        delay = 15 * attempt
        print(f'Retrying NDK download in {delay}s', flush=True)
        time.sleep(delay)


if __name__ == '__main__':
    flutter = os.environ.get('FLUTTER_ROOT')
    if not flutter:
        executable = shutil.which('flutter')
        if not executable:
            raise SystemExit('Flutter must be installed before installing its NDK')
        flutter = Path(executable).resolve().parents[1]
    sdk = os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT')
    if not sdk:
        raise SystemExit('ANDROID_HOME or ANDROID_SDK_ROOT is required')
    install_ndk(sdk, flutter_ndk_version(flutter))
