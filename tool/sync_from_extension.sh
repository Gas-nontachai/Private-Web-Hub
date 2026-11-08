#!/usr/bin/env bash
# Verifies assets/websites.json stays in sync with the Chrome extension's CSS rules.
# Usage: tool/sync_from_extension.sh ../movie-ads-hider-extaintion
set -euo pipefail
ext="${1:?path to extension repo}"
python3 - "$ext" <<'PY'
import json, re, sys
ext = sys.argv[1]
cat = json.load(open("assets/websites.json"))
files = {"serieday": "serieday.css", "037hdd": "037-hdd.css", "goseries4k": "goseries4k.css"}
bad = 0
for site in cat["sites"]:
    css = open(f"{ext}/rules/{files[site['id']]}").read()
    ext_sel = sorted(s.strip() for block in re.findall(r"([^{}]+)\{", css) for s in block.split(",") if s.strip())
    cat_sel = sorted(s for r in site["rules"] for a in r["actions"] if a["type"] == "hide" for s in a["selectors"])
    if ext_sel != cat_sel:
        bad = 1
        print(f"DRIFT {site['id']}:\n  extension: {ext_sel}\n  catalog:   {cat_sel}")
print("in sync" if not bad else "out of sync")
sys.exit(bad)
PY
