#!/usr/bin/env python3
"""Audit a MySQL dump of the `oedict` Oxford dictionary table and load it
into the bundled voccab-dict.sqlite as an `oxford` table.

Usage:
  python3 load_oxford.py --sql oedict.sql --db ../dict/voccab-dict.sqlite [--dry-run]

The audit parses every INSERT tuple, validates field counts and types,
repairs latin1/utf8 double-encoding (mojibake such as "â€”" for an em-dash),
strips literal "\\n" artifacts from headwords, normalizes case and
whitespace, and reports statistics before anything is written.
"""

import argparse
import re
import sqlite3
import sys


def parse_tuples(sql_text):
    """Yield value tuples from INSERT INTO `oedict` ... VALUES (...),(...);"""
    pos = 0
    insert_re = re.compile(r"INSERT INTO `oedict`[^V]*VALUES", re.IGNORECASE)
    while True:
        m = insert_re.search(sql_text, pos)
        if not m:
            return
        i = m.end()
        n = len(sql_text)
        while i < n:
            # skip to opening paren
            while i < n and sql_text[i] not in "(;":
                i += 1
            if i >= n or sql_text[i] == ";":
                break
            i += 1
            fields, buf = [], []
            in_str = False
            while i < n:
                ch = sql_text[i]
                if in_str:
                    if ch == "\\" and i + 1 < n:  # backslash escape
                        nxt = sql_text[i + 1]
                        buf.append({"n": "\n", "t": "\t", "r": "\r"}.get(nxt, nxt))
                        i += 2
                        continue
                    if ch == "'":
                        if i + 1 < n and sql_text[i + 1] == "'":  # doubled quote
                            buf.append("'")
                            i += 2
                            continue
                        in_str = False
                        i += 1
                        continue
                    buf.append(ch)
                    i += 1
                    continue
                if ch == "'":
                    in_str = True
                    i += 1
                elif ch == ",":
                    fields.append("".join(buf).strip())
                    buf = []
                    i += 1
                elif ch == ")":
                    fields.append("".join(buf).strip())
                    yield fields
                    i += 1
                    break
                else:
                    buf.append(ch)
                    i += 1
        pos = i


def demojibake(text):
    """Repair utf8-bytes-read-as-cp1252 (best effort, only when it decodes).

    cp1252 rather than latin1 because the tell-tale sequences (e.g. "â€”"
    for an em-dash) include €/™-range characters that latin1 lacks.
    """
    if not any(ch in text for ch in ("â", "Ã", "Â")):
        return text
    for codec in ("cp1252", "latin1"):
        try:
            return text.encode(codec).decode("utf-8")
        except (UnicodeEncodeError, UnicodeDecodeError):
            continue
    return text


def clean_word(raw):
    w = raw.replace("\\n", " ").replace("\n", " ").strip()
    w = re.sub(r"\s+", " ", w)
    return w


def clean_meaning(raw):
    m = demojibake(raw)
    m = m.replace("\r\n", "\n").replace("\r", "\n")
    m = re.sub(r"[ \t]+", " ", m)
    m = re.sub(r"\n{3,}", "\n\n", m)
    return m.strip()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sql", required=True)
    ap.add_argument("--db", required=True)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    raw = open(args.sql, "rb").read().decode("utf-8", errors="replace")
    rows = list(parse_tuples(raw))

    problems = []
    cleaned = []
    seen = {}
    mojibake_fixed = 0
    for idx, fields in enumerate(rows):
        if len(fields) != 4:
            problems.append(f"row {idx}: {len(fields)} fields")
            continue
        word_id, letter, word, meaning = fields
        if not word_id.isdigit():
            problems.append(f"row {idx}: non-numeric id {word_id!r}")
            continue
        word = clean_word(word)
        fixed = clean_meaning(meaning)
        if fixed != meaning:
            mojibake_fixed += 1
        if not word:
            problems.append(f"row {idx}: empty word")
            continue
        if not fixed:
            problems.append(f"row {idx}: empty meaning for {word!r}")
            continue
        if len(word) > 60:
            problems.append(f"row {idx}: suspicious word length {len(word)}: {word[:40]!r}")
            continue
        key = word.lower()
        if key in seen:
            # keep the longer meaning on duplicates
            if len(fixed) > len(cleaned[seen[key]][1]):
                cleaned[seen[key]] = (word, fixed, letter.lower())
            continue
        seen[key] = len(cleaned)
        cleaned.append((word, fixed, letter.lower()))

    letters = sorted({c[2] for c in cleaned})
    lengths = sorted(len(c[1]) for c in cleaned)
    print(f"tuples parsed:      {len(rows)}")
    print(f"cleaned entries:    {len(cleaned)}")
    print(f"duplicates merged:  {len(rows) - len(cleaned) - len(problems)}")
    print(f"rows cleaned up:    {mojibake_fixed} (mojibake/whitespace/newline artifacts)")
    print(f"problem rows:       {len(problems)}")
    for p in problems[:20]:
        print("  !", p)
    print(f"letters covered:    {''.join(letters)}")
    print(f"meaning length:     min {lengths[0]} / median {lengths[len(lengths)//2]} / max {lengths[-1]}")
    for w, m, _ in (cleaned[0], cleaned[len(cleaned) // 2], cleaned[-1]):
        print(f"  sample: {w!r}: {m[:100]!r}")

    if args.dry_run:
        return

    conn = sqlite3.connect(args.db)
    conn.execute("DROP TABLE IF EXISTS oxford")
    conn.execute(
        """CREATE TABLE oxford (
            word TEXT NOT NULL COLLATE NOCASE,
            meaning TEXT NOT NULL
        )"""
    )
    conn.executemany(
        "INSERT INTO oxford (word, meaning) VALUES (?, ?)",
        [(w, m) for w, m, _ in cleaned],
    )
    conn.execute("CREATE INDEX idx_oxford_word ON oxford(word)")
    conn.commit()
    conn.execute("VACUUM")
    conn.close()
    print(f"loaded {len(cleaned)} entries into {args.db}")


if __name__ == "__main__":
    main()
