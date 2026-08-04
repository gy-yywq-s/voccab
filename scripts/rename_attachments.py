#!/usr/bin/env python3
"""Rename xcresulttool-exported attachments to their human-readable names.

Usage: rename_attachments.py <export-dir>
The export dir must contain manifest.json produced by
`xcrun xcresulttool export attachments`.
"""
import json
import os
import shutil
import sys


def main():
    out = sys.argv[1]
    manifest_path = os.path.join(out, "manifest.json")
    if not os.path.exists(manifest_path):
        print(f"no manifest at {manifest_path}")
        return
    with open(manifest_path) as f:
        manifest = json.load(f)
    for test in manifest:
        for att in test.get("attachments", []):
            src = os.path.join(out, att.get("exportedFileName", ""))
            name = att.get("suggestedHumanReadableName") or att.get("exportedFileName")
            if os.path.exists(src) and name:
                if not name.endswith(".png"):
                    name += ".png"
                dst = os.path.join(out, name)
                shutil.move(src, dst)
                print(f"{att.get('exportedFileName')} -> {name}")


if __name__ == "__main__":
    main()
