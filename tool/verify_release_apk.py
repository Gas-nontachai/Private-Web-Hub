"""Validate a release APK with actionable errors rather than silent shell tests."""
import hashlib
from pathlib import Path
import re
import sys
import zipfile


def validate(apk_file, cert_file, signing_file, badging_file, version, build_number):
    apk_file = Path(apk_file)
    if not apk_file.is_file() or apk_file.stat().st_size == 0:
        raise ValueError(f"Missing or empty APK: {apk_file}")

    signing = Path(signing_file).read_text()
    certificates = re.findall(
        r"^Signer #\d+ certificate SHA-256 digest:\s*([0-9a-fA-F:]+)\s*$",
        signing, flags=re.MULTILINE,
    )
    if len(certificates) != 1:
        raise ValueError(f"Expected one APK signer, got {len(certificates)}. Check apksigner output.")
    expected = hashlib.sha256(Path(cert_file).read_bytes()).hexdigest().lower()
    actual = certificates[0].replace(":", "").lower()
    if actual != expected:
        raise ValueError(
            f"APK signing certificate mismatch: expected {expected}, got {actual}. "
            "Check the Android release keystore, alias, and Gradle signing configuration."
        )
    print("OK: APK signed with configured release certificate")

    badging = Path(badging_file).read_text()
    package_line = next((line for line in badging.splitlines() if line.startswith("package:")), None)
    if not package_line:
        raise ValueError("Android aapt returned no package metadata")
    package = re.search(r"name='([^']+)'", package_line)
    version_name = re.search(r"versionName='([^']+)'", package_line)
    version_code = re.search(r"versionCode=\x27([^\x27]+)\x27", package_line)
    expected_package = "com.nonthachai.privatewebhub"
    if not package or package.group(1) != expected_package:
        raise ValueError(f"Wrong Android applicationId: {package.group(1) if package else package_line}")
    if not version_name or version_name.group(1) != version:
        raise ValueError(
            f"Wrong Android versionName: expected {version}, "
            f"got {version_name.group(1) if version_name else package_line}"
        )
    if not version_code or version_code.group(1) != str(build_number):
        raise ValueError(
            f"Wrong Android versionCode: expected {build_number}, "
            f"got {version_code.group(1) if version_code else package_line}"
        )
    print(f"OK: package {expected_package}, versionName {version}, versionCode {build_number}")

    labels = re.findall(r"^application-label(?:-[^:]*)?:'([^']*)'\s*$", badging, flags=re.MULTILINE)
    if "Movie.exe" not in labels:
        raise ValueError(f"Expected app label 'Movie.exe'; found {labels or '[none]'}")
    print("OK: Android display name Movie.exe")

    with zipfile.ZipFile(apk_file) as apk:
        names = set(apk.namelist())
        for abi in ("armeabi-v7a", "arm64-v8a", "x86_64"):
            candidate = f"lib/{abi}/libflutter.so"
            if candidate not in names:
                raise ValueError(f"Universal APK is missing ABI library {candidate}")
    print("OK: APK contains all three Flutter ABI libraries")


if __name__ == "__main__":
    try:
        validate(*sys.argv[1:])
    except (ValueError, OSError, zipfile.BadZipFile) as error:
        print(f"::error::{error}", file=sys.stderr)
        sys.exit(1)
