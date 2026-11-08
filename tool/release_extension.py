"""Pack and verify CRX3 using the supplied persistent RSA key and OpenSSL."""

import argparse
import base64
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import struct
import subprocess
import tempfile
import zipfile


SIGNATURE_CONTEXT = b"CRX3 SignedData\x00"


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


def varint(value):
    result = bytearray()
    while value >= 128:
        result.append((value & 127) | 128)
        value >>= 7
    result.append(value)
    return bytes(result)


def field(number, value):
    return varint((number << 3) | 2) + varint(len(value)) + value


def fields(data):
    offset = 0

    def read_varint():
        nonlocal offset
        result = 0
        for shift in range(0, 64, 7):
            if offset >= len(data):
                raise ValueError("Truncated CRX protobuf")
            byte = data[offset]
            offset += 1
            result |= (byte & 127) << shift
            if not byte & 128:
                return result
        raise ValueError("Invalid CRX protobuf varint")

    result = {}
    while offset < len(data):
        tag = read_varint()
        if tag & 7 != 2 or tag >> 3 == 0:
            raise ValueError("Unsupported CRX protobuf field")
        size = read_varint()
        if size > len(data) - offset:
            raise ValueError("Truncated CRX protobuf field")
        number = tag >> 3
        if number in result:
            raise ValueError("Duplicate CRX protobuf field")
        result[number] = data[offset:offset + size]
        offset += size
    return result


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


def check_manifest_key(manifest, public_key):
    if "key" in manifest:
        if base64.b64decode(manifest["key"], validate=True) != public_key:
            raise ValueError("Manifest key does not match the persistent signing key")


def pack(source, tag, key, output):
    version = release_version(tag)
    source = Path(source)
    manifest = json.loads((source / "manifest.json").read_text())
    chrome_version(manifest["version"])
    manifest["name"] = "Movie.exe"
    manifest["version"] = version
    subprocess.run(
        ["openssl", "rsa", "-in", str(key), "-passin", "pass:", "-check", "-noout"],
        check=True, stdout=subprocess.DEVNULL,
    )
    public_key = subprocess.check_output(
        ["openssl", "pkey", "-in", str(key), "-passin", "pass:", "-pubout", "-outform", "DER"]
    )
    check_manifest_key(manifest, public_key)
    archive = io.BytesIO()
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as zipped:
        for path in sorted(source.rglob("*")):
            relative = path.relative_to(source)
            if any(part in {".git", ".github", "__pycache__"} for part in relative.parts):
                continue
            if path.name == ".DS_Store" or path.name.startswith("README"):
                continue
            if path.is_symlink():
                raise ValueError("Extension source contains a symlink")
            if not path.is_file():
                continue
            if path.suffix.lower() in {".pem", ".key", ".keystore", ".jks", ".crx", ".zip"}:
                raise ValueError("Extension source contains signing material or a packed artifact")
            if relative.as_posix() == "manifest.json":
                zipped.writestr("manifest.json", json.dumps(manifest, indent=2) + "\n")
            else:
                zipped.write(path, relative.as_posix())
        validate_manifest(manifest, version, set(zipped.namelist()))
    payload = archive.getvalue()
    signed_header = field(1, hashlib.sha256(public_key).digest()[:16])
    signed_data = SIGNATURE_CONTEXT + struct.pack("<I", len(signed_header)) + signed_header + payload
    with tempfile.TemporaryDirectory() as directory:
        data_path = Path(directory, "signed-data")
        data_path.write_bytes(signed_data)
        signature = subprocess.check_output(
            ["openssl", "dgst", "-sha256", "-sign", str(key), "-passin", "pass:", str(data_path)]
        )
    header = field(2, field(1, public_key) + field(2, signature)) + field(10000, signed_header)
    package = b"Cr24" + struct.pack("<II", 3, len(header)) + header + payload
    Path(output).write_bytes(package)
    verify(output, tag, expected_key=public_key)


def chrome_version(version):
    if not isinstance(version, str) or not re.fullmatch(
        r"(0|[1-9][0-9]*)(\.(0|[1-9][0-9]*)){0,3}", version
    ):
        raise ValueError("Invalid source Chrome manifest version")
    parts = [int(part) for part in version.split(".")]
    if any(part > 65535 for part in parts) or not any(parts):
        raise ValueError("Invalid source Chrome manifest version")


def verify(package, tag, expected_key=None):
    version = release_version(tag)
    data = Path(package).read_bytes()
    if len(data) < 12 or data[:4] != b"Cr24":
        raise ValueError("Invalid CRX magic/header")
    crx_version, header_size = struct.unpack("<II", data[4:12])
    if crx_version != 3 or header_size > len(data) - 12:
        raise ValueError("Invalid CRX3 header")
    header = fields(data[12:12 + header_size])
    if set(header) != {2, 10000}:
        raise ValueError("Expected one RSA proof and signed header")
    proof = fields(header[2])
    signed_header = fields(header[10000])
    if set(proof) != {1, 2} or set(signed_header) != {1}:
        raise ValueError("Invalid CRX3 proof")
    public_key = proof[1]
    crx_id = hashlib.sha256(public_key).digest()[:16]
    if signed_header[1] != crx_id or (expected_key is not None and public_key != expected_key):
        raise ValueError("CRX signing identity does not match")
    payload = data[12 + header_size:]
    signed_data = SIGNATURE_CONTEXT + struct.pack("<I", len(header[10000])) + header[10000] + payload
    with tempfile.TemporaryDirectory() as directory:
        directory = Path(directory)
        (directory / "public.der").write_bytes(public_key)
        (directory / "signature").write_bytes(proof[2])
        (directory / "signed-data").write_bytes(signed_data)
        subprocess.run(
            ["openssl", "pkey", "-pubin", "-inform", "DER", "-in", str(directory / "public.der"),
             "-out", str(directory / "public.pem")],
            check=True,
        )
        subprocess.run(
            ["openssl", "dgst", "-sha256", "-verify", str(directory / "public.pem"),
             "-signature", str(directory / "signature"), str(directory / "signed-data")],
            check=True, stdout=subprocess.DEVNULL,
        )
    with zipfile.ZipFile(io.BytesIO(payload)) as zipped:
        names = zipped.namelist()
        if len(names) != len(set(names)) or zipped.testzip() is not None:
            raise ValueError("Corrupt or duplicate CRX archive entries")
        for name in names:
            path = PurePosixPath(name)
            if path.is_absolute() or ".." in path.parts or "\\" in name:
                raise ValueError("Unsafe CRX archive entry")
        manifest = json.loads(zipped.read("manifest.json"))
        validate_manifest(manifest, version, set(names))
        check_manifest_key(manifest, public_key)
    extension_id = "".join(chr(ord("a") + int(char, 16)) for char in crx_id.hex())
    print(f"Validated Movie.exe {version} CRX3; extension ID: {extension_id}")
    return extension_id


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    version = commands.add_parser("version")
    version.add_argument("tag")
    android_code = commands.add_parser("android-code")
    android_code.add_argument("tag")
    package = commands.add_parser("pack")
    for argument in ("source", "tag", "key", "output"):
        package.add_argument(argument)
    validate = commands.add_parser("verify")
    validate.add_argument("package")
    validate.add_argument("tag")
    args = parser.parse_args()
    if args.command == "version":
        print(release_version(args.tag))
    elif args.command == "android-code":
        print(android_build_number(args.tag))
    elif args.command == "pack":
        pack(args.source, args.tag, args.key, args.output)
    else:
        verify(args.package, args.tag)


if __name__ == "__main__":
    main()
