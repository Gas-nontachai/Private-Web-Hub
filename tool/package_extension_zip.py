"""Package the bundled Movie.exe extension for Chrome's Load unpacked flow."""
import argparse
import json
from pathlib import Path
import zipfile

from release_extension import release_version, chrome_version, validate_manifest

EXCLUDE_DIRS = {".git", ".github", "__pycache__"}
SECRET_SUFFIXES = {".pem", ".key", ".keystore", ".jks", ".crx", ".zip"}

def package(source: Path, tag: str, output: Path):
    version = release_version(tag)
    source = source.resolve()
    manifest_file = source / "manifest.json"
    manifest = json.loads(manifest_file.read_text(encoding="utf-8"))
    chrome_version(manifest["version"])
    manifest["name"] = "Movie.exe"
    manifest["version"] = version
    entries = []
    for path in sorted(source.rglob("*")):
        rel = path.relative_to(source)
        if any(part in EXCLUDE_DIRS for part in rel.parts) or path.name == ".DS_Store":
            continue
        if path.is_symlink():
            raise ValueError(f"Symlink not allowed: {rel}")
        if not path.is_file() or path.name.startswith("README"):
            continue
        if path.suffix.lower() in SECRET_SUFFIXES:
            raise ValueError(f"Signing material or packaged file in extension: {rel}")
        entries.append((rel.as_posix(), path))
    names = {name for name, _ in entries}
    validate_manifest(manifest, version, names)
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
        for name, path in entries:
            if name == "manifest.json":
                archive.writestr(name, json.dumps(manifest, indent=2) + "\n")
            else:
                archive.write(path, name)
    with zipfile.ZipFile(output) as archive:
        if archive.testzip() is not None:
            raise ValueError("Invalid ZIP archive")
        packed_manifest = json.loads(archive.read("manifest.json"))
        validate_manifest(packed_manifest, version, set(archive.namelist()))
        if any(name.startswith("extension/") for name in archive.namelist()):
            raise ValueError("ZIP must have manifest.json at the root")
    print(f"Validated Movie.exe extension ZIP: {output}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("tag")
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    package(args.source, args.tag, args.output)
