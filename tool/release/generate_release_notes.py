"""Generate user-focused GitHub Release notes for Movie.exe."""
from __future__ import annotations

import argparse
from pathlib import Path
import subprocess
import sys

from tool.release.release_extension import release_version


ROOT = Path(__file__).resolve().parents[2]
TEMPLATE = ROOT / ".github" / "release-template.md"
REPOSITORY = "Gas-nontachai/Private-Web-Hub"


def previous_tag(tag: str) -> str | None:
    current_version = tuple(map(int, release_version(tag).split(".")))
    result = subprocess.run(
        ["git", "tag", "--list", "v*"],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    candidates = []
    for candidate in result.stdout.splitlines():
        try:
            version = tuple(map(int, release_version(candidate).split(".")))
        except ValueError:
            continue
        if version < current_version:
            candidates.append((version, candidate))
    return max(candidates, default=(None, None))[1]


def render_notes(tag: str, prior_tag: str | None = None) -> str:
    version = release_version(tag)
    if prior_tag is None:
        prior_tag = previous_tag(tag)
    elif prior_tag and tuple(map(int, release_version(prior_tag).split("."))) >= tuple(
        map(int, version.split("."))
    ):
        raise ValueError("Previous release tag must have a lower version")

    apk_filename = f"Movie.exe-{tag}.apk"
    zip_filename = f"Movie.exe-{tag}.zip"
    release_url = f"https://github.com/{REPOSITORY}/releases/download/{tag}"
    if prior_tag:
        changelog_url = (
            f"https://github.com/{REPOSITORY}/compare/{prior_tag}...{tag}"
        )
        changes = "No user-facing change details are provided for this release."
    else:
        changelog_url = f"https://github.com/{REPOSITORY}/commits/{tag}"
        changes = (
            "### Added\n"
            "- Android app for supported movie and series websites.\n"
            "- Chrome extension for supported movie and series websites."
        )

    template = TEMPLATE.read_text(encoding="utf-8")
    values = {
        "VERSION": version,
        "TAG": tag,
        "APK_FILENAME": apk_filename,
        "ZIP_FILENAME": zip_filename,
        "APK_URL": f"{release_url}/{apk_filename}",
        "ZIP_URL": f"{release_url}/{zip_filename}",
        "CHANGES": changes,
        "CHANGELOG_URL": changelog_url,
    }
    for key, value in values.items():
        template = template.replace(f"${{{key}}}", value)
    if "${" in template:
        raise ValueError("Release notes template contains an unresolved value")
    return template


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tag", help="Release tag in vX.Y.Z format")
    parser.add_argument(
        "--previous-tag",
        help="Previous release tag; inferred from repository tags when omitted",
    )
    parser.add_argument("--output", type=Path, help="Write notes to a file instead of stdout")
    args = parser.parse_args()
    notes = render_notes(args.tag, args.previous_tag)
    if args.output:
        args.output.write_text(notes, encoding="utf-8")
    else:
        sys.stdout.write(notes)


if __name__ == "__main__":
    main()
