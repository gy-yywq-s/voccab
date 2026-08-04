#!/usr/bin/env python3
"""Build the bundled dictionary database (voccab-dict.sqlite).

Inputs (not committed to the repo):
  - ecdict.csv     ECDICT English->Chinese dictionary dump
                   (https://github.com/skywind3000/ECDICT, also published in the
                   `ecdict` npm package under assets/ecdict.csv)
  - WordNet 3.1 database files (dict/ directory from
    https://wordnetcode.princeton.edu/wn3.1.dict.tar.gz)
  - ../seed/sat_rw_vocab.csv  words that must always be kept

Output:
  - ../dict/voccab-dict.sqlite  read-only database bundled into the app

Usage:
  python3 build_dict.py --ecdict ecdict.csv --wordnet dict --out ../dict/voccab-dict.sqlite
"""

import argparse
import csv
import os
import re
import sqlite3
import sys

WORD_RE = re.compile(r"^[A-Za-z][A-Za-z'\-\. ]*$")

# Keep the bundle small: common words, exam-tagged words, and anything in the
# seed lists. frq/bnc are corpus ranks (lower = more frequent, 0 = unknown).
MAX_RANK = 50000

WN_POS = {"n": "noun", "v": "verb", "a": "adjective", "s": "adjective", "r": "adverb"}


def load_seed_words(seed_dir):
    words = set()
    if not os.path.isdir(seed_dir):
        return words
    for name in os.listdir(seed_dir):
        if not name.endswith(".csv"):
            continue
        with open(os.path.join(seed_dir, name), newline="", encoding="utf-8") as f:
            for row in csv.DictReader(f):
                w = (row.get("word") or "").strip()
                if w:
                    words.add(w.lower())
    return words


def load_wordnet_lemmas(wn_dir):
    lemmas = set()
    for name in ("index.noun", "index.verb", "index.adj", "index.adv"):
        with open(os.path.join(wn_dir, name), encoding="utf-8") as f:
            for line in f:
                if line.startswith("  "):
                    continue
                lemmas.add(line.split()[0].replace("_", " ").lower())
    return lemmas


def keep(row, seed, wn_lemmas):
    word = row["word"]
    if not WORD_RE.match(word) or len(word) > 40:
        return False
    if word.lower() in seed:
        return True
    if word.lower() in wn_lemmas:
        return True
    tag = (row["tag"] or "").strip()
    if tag:
        return True
    try:
        oxford = int(row["oxford"] or 0)
        collins = int(row["collins"] or 0)
        frq = int(row["frq"] or 0)
        bnc = int(row["bnc"] or 0)
    except ValueError:
        return False
    if oxford >= 1 or collins >= 1:
        return True
    if 0 < frq <= MAX_RANK or 0 < bnc <= MAX_RANK:
        return True
    return False


def build_words(conn, ecdict_path, seed, wn_lemmas):
    cur = conn.cursor()
    cur.execute(
        """CREATE TABLE words (
            id INTEGER PRIMARY KEY,
            word TEXT NOT NULL UNIQUE COLLATE NOCASE,
            phonetic TEXT NOT NULL DEFAULT '',
            translation TEXT NOT NULL DEFAULT '',
            definition TEXT NOT NULL DEFAULT '',
            pos TEXT NOT NULL DEFAULT '',
            collins INTEGER NOT NULL DEFAULT 0,
            oxford INTEGER NOT NULL DEFAULT 0,
            tag TEXT NOT NULL DEFAULT '',
            bnc INTEGER NOT NULL DEFAULT 0,
            frq INTEGER NOT NULL DEFAULT 0,
            exchange TEXT NOT NULL DEFAULT ''
        )"""
    )
    kept = 0
    with open(ecdict_path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        batch = []
        for row in reader:
            if not keep(row, seed, wn_lemmas):
                continue
            batch.append(
                (
                    row["word"].strip(),
                    (row["phonetic"] or "").strip(),
                    (row["translation"] or "").replace("\\n", "\n").strip(),
                    (row["definition"] or "").replace("\\n", "\n").strip(),
                    (row["pos"] or "").strip(),
                    int(row["collins"] or 0),
                    int(row["oxford"] or 0),
                    (row["tag"] or "").strip(),
                    int(row["bnc"] or 0),
                    int(row["frq"] or 0),
                    (row["exchange"] or "").strip(),
                )
            )
            kept += 1
            if len(batch) >= 5000:
                cur.executemany(
                    "INSERT OR IGNORE INTO words (word,phonetic,translation,definition,pos,collins,oxford,tag,bnc,frq,exchange) VALUES (?,?,?,?,?,?,?,?,?,?,?)",
                    batch,
                )
                batch = []
        if batch:
            cur.executemany(
                "INSERT OR IGNORE INTO words (word,phonetic,translation,definition,pos,collins,oxford,tag,bnc,frq,exchange) VALUES (?,?,?,?,?,?,?,?,?,?,?)",
                batch,
            )
    cur.execute("CREATE INDEX idx_words_frq ON words(frq)")
    conn.commit()
    return kept


def parse_wordnet(wn_dir, wanted):
    """Yield (word, pos, sense_num, gloss, examples, synonyms)."""
    for pos_key, data_name in (("n", "data.noun"), ("v", "data.verb"), ("a", "data.adj"), ("r", "data.adv")):
        index_name = {"n": "index.noun", "v": "index.verb", "a": "index.adj", "r": "index.adv"}[pos_key]
        offsets_gloss = {}
        offset_members = {}
        with open(os.path.join(wn_dir, data_name), encoding="utf-8") as f:
            for line in f:
                if line.startswith("  "):
                    continue
                head, _, gloss = line.partition("|")
                gloss = gloss.strip()
                fields = head.split()
                offset = fields[0]
                w_cnt = int(fields[3], 16)
                members = []
                for i in range(w_cnt):
                    lemma = fields[4 + i * 2].replace("_", " ")
                    members.append(lemma)
                # Split gloss into definition and quoted examples.
                parts = [p.strip() for p in gloss.split(";")]
                defs, examples = [], []
                for p in parts:
                    if p.startswith('"') and p.endswith('"'):
                        examples.append(p.strip('"'))
                    else:
                        defs.append(p)
                offsets_gloss[offset] = ("; ".join(defs), " | ".join(examples))
                offset_members[offset] = members
        with open(os.path.join(wn_dir, index_name), encoding="utf-8") as f:
            for line in f:
                if line.startswith("  "):
                    continue
                fields = line.split()
                lemma = fields[0].replace("_", " ")
                if lemma not in wanted:
                    continue
                p_cnt = int(fields[3])
                synset_cnt = int(fields[2])
                offsets = fields[4 + p_cnt + 2 :]
                assert len(offsets) == synset_cnt, (lemma, len(offsets), synset_cnt)
                for sense_num, off in enumerate(offsets, start=1):
                    gloss, examples = offsets_gloss[off]
                    syns = [m for m in offset_members[off] if m.lower() != lemma]
                    yield (
                        lemma,
                        WN_POS[pos_key],
                        sense_num,
                        gloss,
                        examples,
                        ", ".join(dict.fromkeys(syns)),
                    )


def build_wordnet(conn, wn_dir):
    cur = conn.cursor()
    cur.execute(
        """CREATE TABLE wordnet (
            word TEXT NOT NULL COLLATE NOCASE,
            pos TEXT NOT NULL,
            sense_num INTEGER NOT NULL,
            gloss TEXT NOT NULL,
            examples TEXT NOT NULL DEFAULT '',
            synonyms TEXT NOT NULL DEFAULT ''
        )"""
    )
    wanted = {r[0].lower() for r in cur.execute("SELECT word FROM words")}
    rows = list(parse_wordnet(wn_dir, wanted))
    cur.executemany("INSERT INTO wordnet VALUES (?,?,?,?,?,?)", rows)
    cur.execute("CREATE INDEX idx_wordnet_word ON wordnet(word)")
    conn.commit()
    return len(rows)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ecdict", required=True)
    ap.add_argument("--wordnet", required=True, help="WordNet dict/ directory")
    ap.add_argument("--seed", default=os.path.join(os.path.dirname(__file__), "..", "seed"))
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    if os.path.exists(args.out):
        os.remove(args.out)
    conn = sqlite3.connect(args.out)
    conn.execute("PRAGMA page_size=4096")

    seed = load_seed_words(args.seed)
    print(f"seed words: {len(seed)}", file=sys.stderr)
    wn_lemmas = load_wordnet_lemmas(args.wordnet)
    print(f"wordnet lemmas: {len(wn_lemmas)}", file=sys.stderr)
    kept = build_words(conn, args.ecdict, seed, wn_lemmas)
    print(f"ecdict rows kept: {kept}", file=sys.stderr)
    wn = build_wordnet(conn, args.wordnet)
    print(f"wordnet senses: {wn}", file=sys.stderr)
    conn.execute("VACUUM")
    conn.close()
    print(f"wrote {args.out} ({os.path.getsize(args.out)/1e6:.1f} MB)", file=sys.stderr)


if __name__ == "__main__":
    main()
