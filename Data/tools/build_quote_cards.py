#!/usr/bin/env python3
"""Literature quote-card gallery: real sentences from public-domain classics
that genuinely contain SAT-band words, typeset as warm paper cards with
EB Garamond. The target word's highlight box is computed from the actual
text layout, pixel-accurate — the in-app lookup demo runs on real text,
which is exactly the app's photograph-a-page use case.

Words come from build_promo_wordfirst.USER_WORDS + SAT_CLASSICS.
Sentences come from Project Gutenberg texts (cached in Data/tools/cache).
"""
import argparse
import json
import random
import re
import sys
import urllib.request
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_promo as bp
import build_promo_wordfirst as wf

REPO = bp.REPO
CACHE = REPO / "Data" / "tools" / "cache" / "gutenberg"
PREVIEW_DIR = REPO / "Data" / "tools" / "preview"

BOOKS = [
    (1342, "Pride and Prejudice", "Jane Austen", 1813),
    (158, "Emma", "Jane Austen", 1815),
    (2701, "Moby-Dick", "Herman Melville", 1851),
    (84, "Frankenstein", "Mary Shelley", 1818),
    (1400, "Great Expectations", "Charles Dickens", 1861),
    (98, "A Tale of Two Cities", "Charles Dickens", 1859),
    (174, "The Picture of Dorian Gray", "Oscar Wilde", 1890),
    (205, "Walden", "Henry David Thoreau", 1854),
    (16643, "Essays", "Ralph Waldo Emerson", 1841),
    (1260, "Jane Eyre", "Charlotte Brontë", 1847),
    (768, "Wuthering Heights", "Emily Brontë", 1847),
    (33, "The Scarlet Letter", "Nathaniel Hawthorne", 1850),
    (120, "Treasure Island", "Robert Louis Stevenson", 1883),
    (1661, "The Adventures of Sherlock Holmes", "Arthur Conan Doyle", 1892),
    (345, "Dracula", "Bram Stoker", 1897),
    (76, "Adventures of Huckleberry Finn", "Mark Twain", 1884),
    (2600, "War and Peace", "Leo Tolstoy", 1869),
    (135, "Les Misérables", "Victor Hugo", 1862),
    (36, "The War of the Worlds", "H. G. Wells", 1898),
    (219, "Heart of Darkness", "Joseph Conrad", 1899),
]

FONT_DIR = Path("/usr/share/fonts/opentype/ebgaramond")
FONT_REGULAR = FONT_DIR / "EBGaramond08-Regular.otf"
FONT_ITALIC = FONT_DIR / "EBGaramond08-Italic.otf"

W, H = 900, 1200
MARGIN = 96
PAPERS = ["#f6f1e7", "#f3ece0", "#eef0ea", "#f4efe9", "#efe9dc", "#f2eee6"]
INK = "#2b2620"
FADE = "#7a6f5f"


def fetch_book(book_id):
    CACHE.mkdir(parents=True, exist_ok=True)
    path = CACHE / f"{book_id}.txt"
    if path.exists():
        return path.read_text(errors="ignore")
    for pattern in (f"https://www.gutenberg.org/files/{book_id}/{book_id}-0.txt",
                    f"https://www.gutenberg.org/cache/epub/{book_id}/pg{book_id}.txt"):
        try:
            req = urllib.request.Request(pattern, headers={"User-Agent": "VoccabQuoteCards/1.0"})
            with urllib.request.urlopen(req, timeout=120) as resp:
                text = resp.read().decode("utf-8", errors="ignore")
            path.write_text(text)
            return text
        except Exception:
            continue
    return ""


def strip_gutenberg(text):
    start = re.search(r"\*\*\* START OF.*?\*\*\*", text, re.S)
    end = re.search(r"\*\*\* END OF", text)
    if start:
        text = text[start.end():]
    if end:
        text = text[:end.start()] if not start else text[:max(0, end.start() - start.end())]
    return text


def sentences_with(flat, word):
    """Sentences containing the exact word (text pre-flattened once)."""
    results = []
    for match in re.finditer(rf"[^.!?]*\b{re.escape(word)}\b[^.!?]*[.!?]", flat, re.I):
        sentence = match.group(0).strip()
        sentence = re.sub(r"^[^A-Z“\"']+", "", sentence)
        if not (60 <= len(sentence) <= 220):
            continue
        if sentence.count('"') % 2 or sentence.count("_") or "CHAPTER" in sentence:
            continue
        # exact-case word must appear as its own token
        if not re.search(rf"\b{re.escape(word)}\b", sentence, re.I):
            continue
        results.append(sentence)
    return results


def wrap(draw, text, font, max_width):
    lines, line = [], ""
    for token in text.split(" "):
        trial = (line + " " + token).strip()
        if draw.textlength(trial, font=font) <= max_width:
            line = trial
        else:
            if line:
                lines.append(line)
            line = token
    if line:
        lines.append(line)
    return lines


def render_card(sentence, word, book, index):
    title, author, year = book[1], book[2], book[3]
    img = Image.new("RGB", (W, H), PAPERS[index % len(PAPERS)])
    draw = ImageDraw.Draw(img)

    # faint rule ornament top + bottom
    draw.rectangle([MARGIN, 150, W - MARGIN, 152], fill="#d9d0bf")
    draw.rectangle([MARGIN, H - 150, W - MARGIN, H - 148], fill="#d9d0bf")

    size = 52 if len(sentence) < 130 else (46 if len(sentence) < 175 else 40)
    font = ImageFont.truetype(str(FONT_REGULAR), size)
    line_gap = int(size * 1.42)
    lines = wrap(draw, sentence, font, W - 2 * MARGIN)
    while len(lines) > 8 and size > 34:
        size -= 4
        font = ImageFont.truetype(str(FONT_REGULAR), size)
        line_gap = int(size * 1.42)
        lines = wrap(draw, sentence, font, W - 2 * MARGIN)

    block_height = len(lines) * line_gap
    y = max(200, (H - block_height) // 2 - 60)

    box = None
    pattern = re.compile(rf"\b{re.escape(word)}\b", re.I)
    for line in lines:
        draw.text((MARGIN, y), line, font=font, fill=INK)
        match = pattern.search(line)
        if match and box is None:
            prefix_width = draw.textlength(line[:match.start()], font=font)
            word_width = draw.textlength(match.group(0), font=font)
            ascent, descent = font.getmetrics()
            box = (int(MARGIN + prefix_width), int(y),
                   int(word_width), int(ascent + descent))
        y += line_gap

    caption_font = ImageFont.truetype(str(FONT_ITALIC), 27)
    caption = f"— {author}, {title} ({year})"
    caption_width = draw.textlength(caption, font=caption_font)
    draw.text(((W - caption_width) / 2, H - 128), caption, font=caption_font, fill=FADE)

    return img, box


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", type=int, default=100)
    args = parser.parse_args()

    dictionary = bp.Dict()
    words = []
    seen = set()
    for word in wf.USER_WORDS + wf.SAT_CLASSICS:
        lower = word.lower()
        if lower in seen:
            continue
        seen.add(lower)
        if dictionary.lookup(lower):
            words.append(lower)

    print(f"loading {len(BOOKS)} classics…", flush=True)
    corpora = []
    for book in BOOKS:
        text = strip_gutenberg(fetch_book(book[0]))
        if len(text) > 10000:
            corpora.append((book, re.sub(r"\s+", " ", text)))
        print(f"  {book[1]}: {len(text)//1000}k chars", flush=True)

    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    for old in PREVIEW_DIR.glob("*.jpg"):
        old.unlink()

    progress_path = REPO / "Data" / "tools" / "promo_progress.json"
    rng = random.Random(11)
    slides = []
    used_books = {}
    attempted = 0
    for word in words:
        if len(slides) >= args.target:
            break
        attempted += 1
        candidates = []
        for book, text in corpora:
            for sentence in sentences_with(text, word)[:3]:
                candidates.append((book, sentence))
        if not candidates:
            continue
        # spread across authors: least-used book first, then shorter sentence
        candidates.sort(key=lambda c: (used_books.get(c[0][0], 0), len(c[1])))
        book, sentence = candidates[0]
        img, box = render_card(sentence, word, book, len(slides))
        if box is None:
            continue
        used_books[book[0]] = used_books.get(book[0], 0) + 1
        norm = (box[0] / W, box[1] / H, box[2] / W, box[3] / H)
        slides.append({
            "title": f"{book[1]} — {book[2]} ({book[3]})",
            "word": word, "conf": 100.0, "image": img, "box": norm,
        })
        preview = img.copy()
        preview.thumbnail((300, 400))
        preview.save(PREVIEW_DIR / f"{len(slides):03d}-{word}.jpg", "JPEG", quality=70)
        progress_path.write_text(json.dumps({
            "processed": attempted, "queued": len(words),
            "accepted": len(slides), "target": args.target,
            "words": [s["word"] for s in slides],
        }, ensure_ascii=False))
        print(f"  [{len(slides):3d}] {word:<16} {book[1][:34]}", flush=True)

    print(f"Accepted {len(slides)} quote cards; writing assets…", flush=True)
    bp.write_assets(slides)
    manifest = [{k: s[k] for k in ("title", "word", "conf", "box")} for s in slides]
    (REPO / "Data" / "tools" / "promo_manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False))
    print("Done.", flush=True)


if __name__ == "__main__":
    main()
