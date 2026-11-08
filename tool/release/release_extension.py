"""Release version and Manifest V3 validation (APK and ZIP only)."""
import argparse
import re


def release_version(tag):
    if not re.fullmatch(r"v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", tag):
        raise ValueError("Release tag must be vX.Y.Z, without leading zeros or suffixes")
    parts = [int(part) for part in tag[1:].split(".")]
    if any(part > 65535 for part in parts) or not any(parts):
        raise ValueError("Chrome version components must be 0..65535 and not all zero")
    return ".".join(map(str, parts))


def android_build_number(tag):
    """Monotonic Android versionCode from vMAJOR.MINOR.PATCH (max 2_100_000_000)."""
    major, minor, patch = map(int, release_version(tag).split("."))
    if minor > 999 or patch > 999:
        raise ValueError("Android versionCode requires MINOR and PATCH <= 999")
    code = major * 1_000_000 + minor * 1_000 + patch
    if code > 2_100_000_000:
        raise ValueError("Android versionCode must be <= 2100000000")
    return code


def validate_manifest(manifest, version, names):
    if manifest.get("manifest_version") != 3:
        raise ValueError("Expected a Manifest V3 extension")
    if manifest.get("name") != "Movie.exe" or manifest.get("version") != version:
        raise ValueError("Extension name/version does not match the release")
    resources = list(manifest.get("icons", {}).values())
    action = manifest.get("action", {})
    icons = action.get("default_icon", {})
    resources.extend([icons] if isinstance(icons, str) else icons.values())
    if action.get("default_popup"):
        resources.append(action["default_popup"])
    for script in manifest.get("content_scripts", []):
        if not script.get("matches"):
            raise ValueError("Content script is missing host matches")
        resources.extend(script.get("js", []))
        resources.extend(script.get("css", []))
    background = manifest.get("background", {})
    if background.get("service_worker"):
        resources.append(background["service_worker"])
    for resource in resources:
        if not isinstance(resource, str) or resource not in names:
            raise ValueError("Manifest references a missing packaged resource")


def chrome_version(version):
    if not isinstance(version, str) or not re.fullmatch(
        r"(0|[1-9][0-9]*)(\.(0|[1-9][0-9]*)){0,3}", version
    ):
        raise ValueError("Invalid source Chrome manifest version")
    parts = [int(part) for part in version.split(".")]
    if any(part > 65535 for part in parts) or not any(parts):
        raise ValueError("Invalid source Chrome manifest version")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("version", "android-code"))
    parser.add_argument("tag")
    args = parser.parse_args()
    print(release_version(args.tag) if args.command == "version" else android_build_number(args.tag))


if __name__ == "__main__":
    main()
