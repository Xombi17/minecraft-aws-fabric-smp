#!/usr/bin/env python3
"""Resolve Modrinth Fabric mods + required dependencies for a target Minecraft version."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import urllib.parse
import urllib.request


def get_json(url: str) -> dict | list:
    req = urllib.request.Request(url, headers={"User-Agent": "mc-aws-template/1.0"})
    with urllib.request.urlopen(req, timeout=20) as resp:
        return json.loads(resp.read().decode("utf-8"))


def pick_version(pid: str, mc_version: str) -> dict | None:
    gvs = urllib.parse.quote(json.dumps([mc_version]))
    lds = urllib.parse.quote('["fabric"]')
    vers = get_json(f"https://api.modrinth.com/v2/project/{pid}/version?game_versions={gvs}&loaders={lds}")
    if not vers:
        return None
    # Prefer release > beta > alpha
    rank = {"release": 0, "beta": 1, "alpha": 2}
    vers.sort(key=lambda v: rank.get(v.get("version_type", "alpha"), 3))
    return vers[0]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--mc-version", required=True)
    ap.add_argument("--mod-list", required=True)
    ap.add_argument("--manifest-out", required=True)
    ap.add_argument("--download-dir", default="")
    args = ap.parse_args()

    with open(args.mod_list, "r", encoding="utf-8") as f:
        queue = [
            ln.split("#", 1)[0].strip()
            for ln in f
            if ln.split("#", 1)[0].strip()
        ]

    resolved: dict[str, dict] = {}
    visited_ids: set[str] = set()
    skipped: list[str] = []

    while queue:
        item = queue.pop(0)
        try:
            proj = get_json(f"https://api.modrinth.com/v2/project/{urllib.parse.quote(item)}")
        except Exception as exc:
            print(f"[WARN] Could not resolve project '{item}': {exc}", file=sys.stderr)
            skipped.append(item)
            continue

        pid = proj["id"]
        slug = proj["slug"]
        if pid in visited_ids:
            continue
        visited_ids.add(pid)

        ver = pick_version(pid, args.mc_version)
        if not ver:
            print(f"[WARN] No Fabric {args.mc_version} build for '{slug}' ({pid}); skipping.", file=sys.stderr)
            skipped.append(slug)
            continue

        primary = next((x for x in ver["files"] if x.get("primary")), ver["files"][0])
        resolved[pid] = {
            "name": slug,
            "project_id": pid,
            "version": ver["version_number"],
            "version_id": ver["id"],
            "version_type": ver["version_type"],
            "filename": primary["filename"],
            "url": primary["url"],
            "sha512": primary["hashes"]["sha512"],
            "source": f"https://modrinth.com/mod/{slug}/version/{ver['id']}",
        }
        print(f"[OK] {slug:24s} -> {ver['version_number']} ({ver['version_type']})")

        for dep in ver.get("dependencies", []):
            if dep.get("dependency_type") == "required" and dep.get("project_id"):
                dep_id = dep["project_id"]
                if dep_id not in visited_ids:
                    queue.append(dep_id)

    manifest = list(resolved.values())
    os.makedirs(os.path.dirname(os.path.abspath(args.manifest_out)), exist_ok=True)
    with open(args.manifest_out, "w", encoding="utf-8") as out:
        json.dump(manifest, out, indent=2)

    if args.download_dir:
        os.makedirs(args.download_dir, exist_ok=True)
        for m in manifest:
            dest = os.path.join(args.download_dir, m["filename"])
            if os.path.exists(dest):
                with open(dest, "rb") as existing:
                    if hashlib.sha512(existing.read()).hexdigest() == m["sha512"]:
                        continue
            req = urllib.request.Request(m["url"], headers={"User-Agent": "mc-aws-template/1.0"})
            data = urllib.request.urlopen(req, timeout=30).read()
            if hashlib.sha512(data).hexdigest() != m["sha512"]:
                raise RuntimeError(f"SHA-512 verification failed for {m['filename']}")
            with open(dest, "wb") as out:
                out.write(data)
            print(f"[DL] {m['filename']} ({len(data)} bytes, SHA-512 verified)")

    if skipped:
        print(f"[INFO] Skipped mods without {args.mc_version} Fabric builds: {', '.join(skipped)}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
