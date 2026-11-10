#!/usr/bin/env python3
"""Download Vanilla Tweaks datapacks matching a JSON config for a target Minecraft version."""

from __future__ import annotations

import argparse
import io
import json
import os
import sys
import urllib.parse
import urllib.request
import zipfile


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--mc-version", required=True)
    ap.add_argument("--config", required=True)
    ap.add_argument("--out-dir", required=True)
    args = ap.parse_args()

    with open(args.config, "r", encoding="utf-8") as f:
        wanted_cfg: dict[str, list[str]] = json.load(f)

    cat_url = f"https://vanillatweaks.net/assets/resources/json/{args.mc_version}/dpcategories.json"
    try:
        req = urllib.request.Request(cat_url, headers={"User-Agent": "Mozilla/5.0"})
        cat_data = json.loads(urllib.request.urlopen(req, timeout=20).read().decode("utf-8"))
    except Exception as exc:
        print(f"[WARN] Vanilla Tweaks catalog unavailable for MC {args.mc_version}: {exc}", file=sys.stderr)
        return 0

    available: dict[str, set[str]] = {}
    for cat in cat_data.get("categories", []):
        available[cat["category"].lower()] = {p["name"] for p in cat.get("packs", [])}

    selected: dict[str, list[str]] = {}
    for cat_name, pack_names in wanted_cfg.items():
        avail_set = available.get(cat_name.lower(), set())
        matched = [p for p in pack_names if p in avail_set]
        missing = [p for p in pack_names if p not in avail_set]
        if missing:
            print(f"[WARN] Packs unavailable in Vanilla Tweaks {args.mc_version} ({cat_name}): {', '.join(missing)}", file=sys.stderr)
        if matched:
            selected[cat_name.lower()] = matched

    if not selected:
        print("[WARN] No matching Vanilla Tweaks datapacks found to download.", file=sys.stderr)
        return 0

    payload = urllib.parse.urlencode({"packs": json.dumps(selected), "version": args.mc_version}).encode("utf-8")
    dl_req = urllib.request.Request(
        "https://vanillatweaks.net/assets/server/zipdatapacks.php",
        data=payload,
        headers={"User-Agent": "Mozilla/5.0", "Referer": "https://vanillatweaks.net/picker/datapacks/"},
    )
    resp = json.loads(urllib.request.urlopen(dl_req, timeout=30).read().decode("utf-8"))
    if resp.get("status") != "success":
        print(f"[WARN] Vanilla Tweaks zip build failed: {resp}", file=sys.stderr)
        return 0

    zip_url = "https://vanillatweaks.net" + resp["link"]
    raw_zip = urllib.request.urlopen(urllib.request.Request(zip_url, headers={"User-Agent": "Mozilla/5.0"}), timeout=30).read()
    os.makedirs(args.out_dir, exist_ok=True)
    with zipfile.ZipFile(io.BytesIO(raw_zip)) as zf:
        for member in zf.namelist():
            if member.endswith(".zip"):
                target = os.path.join(args.out_dir, os.path.basename(member))
                with open(target, "wb") as out:
                    out.write(zf.read(member))
                print(f"[OK] Datapack: {os.path.basename(member)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
