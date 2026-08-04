#!/usr/bin/env python3
"""Builds voccab-extras.sqlite: additional open dictionary/thesaurus sources.

- webster: GCIDE (GNU Collaborative International Dictionary, the maintained
  machine-readable Webster's 1913) — public domain / GPL data.
- moby: Moby Thesaurus II (Grady Ward, public domain) — the largest English
  thesaurus.

Both tables are filtered to headwords present in the main voccab-dict.sqlite
so the bundle stays reasonable. Kept as a separate DB file so each bundled
file stays well under GitHub's 100 MB per-file limit.
"""
import html
import io
import re
import sqlite3
import sys
import tarfile
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
DICT_DB = REPO / "Data" / "dict" / "voccab-dict.sqlite"
OUT_DB = REPO / "Data" / "dict" / "voccab-extras.sqlite"
CACHE = REPO / "Data" / "tools" / "cache"

MOBY_URL = "https://www.gutenberg.org/files/3202/files/mthesaur.txt"
GCIDE_URL = "https://ftp.gnu.org/gnu/gcide/gcide-0.53.tar.gz"

MAX_SYNONYMS = 60


def download(url, name):
    CACHE.mkdir(parents=True, exist_ok=True)
    path = CACHE / name
    if path.exists():
        return path
    print(f"downloading {url}")
    req = urllib.request.Request(url, headers={"User-Agent": "VoccabExtras/1.0"})
    with urllib.request.urlopen(req, timeout=600) as resp, open(path, "wb") as f:
        while chunk := resp.read(1 << 20):
            f.write(chunk)
    return path


def keep_set():
    conn = sqlite3.connect(DICT_DB)
    words = {r[0].lower() for r in conn.execute("SELECT word FROM words")}
    conn.close()
    print(f"keep set: {len(words)} words")
    return words


def build_moby(cur, keep):
    path = download(MOBY_URL, "mthesaur.txt")
    count = 0
    for line in open(path, encoding="latin1"):
        parts = [p.strip() for p in line.strip().split(",") if p.strip()]
        if len(parts) < 2:
            continue
        root = parts[0].lower()
        if root not in keep:
            continue
        synonyms = [s for s in parts[1:] if s.lower() in keep and s.lower() != root]
        if not synonyms:
            continue
        cur.execute("INSERT OR IGNORE INTO moby VALUES (?,?)",
                    (parts[0], ",".join(synonyms[:MAX_SYNONYMS])))
        count += 1
    print(f"moby: {count} entries")


ENT_RE = re.compile(r"<ent>([^<]+)</ent>")
DEF_RE = re.compile(r"<def>(.*?)</def>", re.S)
POS_RE = re.compile(r"<pos>([^<]*)</pos>")
TAG_RE = re.compile(r"<[^>]+>")


def clean(text):
    text = TAG_RE.sub("", text)
    text = html.unescape(text)
    text = text.replace("\\'d8", "").replace("\\'d4", "")
    text = re.sub(r"\\'[0-9a-f]{2}", "", text)
    return re.sub(r"\s+", " ", text).strip()


def build_webster(cur, keep):
    path = download(GCIDE_URL, "gcide.tar.gz")
    entries = {}
    with tarfile.open(path, "r:gz") as tar:
        for member in tar.getmembers():
            name = Path(member.name).name
            if not re.fullmatch(r"CIDE\.[A-Z]", name):
                continue
            raw = tar.extractfile(member).read().decode("latin1")
            # An entry block runs from one <p><ent> to the next.
            blocks = re.split(r"(?=<p><ent>)", raw)
            for block in blocks:
                ent_match = ENT_RE.search(block)
                if not ent_match:
                    continue
                word = clean(ent_match.group(1))
                lower = word.lower()
                if lower not in keep:
                    continue
                pos_match = POS_RE.search(block)
                pos = clean(pos_match.group(1)) if pos_match else ""
                defs = [clean(d) for d in DEF_RE.findall(block)]
                defs = [d for d in defs if d]
                if not defs:
                    continue
                numbered = defs if len(defs) == 1 else [
                    f"{i}. {d}" for i, d in enumerate(defs, 1)]
                text = (f"({pos}) " if pos else "") + "\n".join(numbered)
                # Merge multiple blocks for the same headword.
                if lower in entries:
                    entries[lower] = (entries[lower][0],
                                      entries[lower][1] + "\n" + text)
                else:
                    entries[lower] = (word, text)
    for word, text in entries.values():
        cur.execute("INSERT OR IGNORE INTO webster VALUES (?,?)", (word, text))
    print(f"webster: {len(entries)} entries")


def main():
    keep = keep_set()
    if OUT_DB.exists():
        OUT_DB.unlink()
    conn = sqlite3.connect(OUT_DB)
    cur = conn.cursor()
    cur.execute("CREATE TABLE webster (word TEXT NOT NULL COLLATE NOCASE, definition TEXT NOT NULL)")
    cur.execute("CREATE TABLE moby (word TEXT NOT NULL COLLATE NOCASE, synonyms TEXT NOT NULL)")
    build_moby(cur, keep)
    build_webster(cur, keep)
    cur.execute("CREATE INDEX idx_webster_word ON webster(word)")
    cur.execute("CREATE INDEX idx_moby_word ON moby(word)")
    conn.commit()
    cur.execute("VACUUM")
    conn.close()
    size = OUT_DB.stat().st_size / 1e6
    print(f"done: {OUT_DB} ({size:.1f} MB)")


if __name__ == "__main__":
    main()
