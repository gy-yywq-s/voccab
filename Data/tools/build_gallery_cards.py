#!/usr/bin/env python3
"""Book-plate gallery: a real public-domain painting on warm paper with a
literature caption underneath that genuinely contains the SAT target word.
The 19th-century illustrated-plate format — image-first (it's a gallery),
but the word is truly printed inside the image, in the caption zone, so the
in-app lookup highlight lands on real text.

Paintings: Google Art Project museum scans on Wikimedia Commons.
Captions: sentences from 20 Gutenberg classics (build_quote_cards corpus).
"""
import argparse
import io
import json
import random
import re
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_promo as bp
import build_promo_wordfirst as wf
import build_quote_cards as qc

REPO = bp.REPO
PREVIEW_DIR = REPO / "Data" / "tools" / "preview"

PAINTERS = [
    "Claude Monet", "J. M. W. Turner", "Vincent van Gogh",
    "Caspar David Friedrich", "Katsushika Hokusai", "Utagawa Hiroshige",
    "Albert Bierstadt", "Camille Corot", "Johannes Vermeer",
    "John Constable", "James McNeill Whistler", "Camille Pissarro",
    "Edgar Degas", "Paul Cézanne", "John Singer Sargent",
    "Winslow Homer", "Ivan Aivazovsky", "Rembrandt",
    "Pierre-Auguste Renoir", "Gustave Caillebotte",
]
PER_PAINTER = 10

W, H = 900, 1200
MARGIN = 56
ART_TOP = 56
ART_MAX_H = 700
INK = "#2b2620"
FADE = "#7a6f5f"


def harvest_paintings():
    """(painter, title) pairs from Google Art Project categories."""
    results = []
    for painter in PAINTERS:
        try:
            data = bp.api_get({
                "action": "query", "list": "categorymembers",
                "cmtitle": f"Category:Google Art Project works by {painter}",
                "cmtype": "file", "cmlimit": 50,
            })
            files = [m["title"] for m in data["query"]["categorymembers"]
                     if m["title"].lower().endswith((".jpg", ".jpeg", ".png"))]
        except Exception:
            files = []
        if not files:
            try:
                data = bp.api_get({
                    "action": "query", "list": "search", "srnamespace": 6,
                    "srlimit": 20,
                    "srsearch": f'intitle:"{painter}" filetype:bitmap incategory:"Google Art Project"',
                })
                files = [m["title"] for m in data["query"]["search"]
                         if m["title"].lower().endswith((".jpg", ".jpeg", ".png"))]
            except Exception:
                files = []
        random.Random(painter).shuffle(files)
        for title in files[:PER_PAINTER]:
            results.append((painter, title))
        print(f"  {painter}: {min(len(files), PER_PAINTER)} works", flush=True)
    return results


def textured_paper(width, height, tone):
    """Photographed-paper base: grain, fibers, edge shading."""
    paper = Image.new("RGB", (width, height), tone)
    grain = Image.effect_noise((width, height), 13).convert("L")
    paper = Image.composite(
        paper.point(lambda v: max(0, v - 10)), paper,
        grain.point(lambda v: 255 if v < 100 else 0))
    shade = Image.new("L", (width, height), 0)
    sd = ImageDraw.Draw(shade)
    for i in range(60):
        alpha = int(26 * (1 - i / 60))
        sd.rectangle([i, i, width - 1 - i, height - 1 - i], outline=alpha)
    paper = Image.composite(paper.point(lambda v: max(0, v - 18)), paper, shade)
    return paper.filter(ImageFilter.GaussianBlur(0.4))


def compose(painting, painter, sentence, word, index):
    img = textured_paper(W, H, qc.PAPERS[index % len(qc.PAPERS)])
    draw = ImageDraw.Draw(img)

    # Artwork plate, fitted, thin ink border.
    art = painting.copy()
    art.thumbnail((W - 2 * MARGIN, ART_MAX_H))
    ax = (W - art.width) // 2
    ay = ART_TOP + (ART_MAX_H - art.height) // 2
    img.paste(art, (ax, ay))
    draw.rectangle([ax - 2, ay - 2, ax + art.width + 1, ay + art.height + 1],
                   outline="#4a4238", width=2)

    # Caption: the literature sentence, word highlighted downstream.
    size = 34 if len(sentence) < 120 else 30
    font = ImageFont.truetype(str(qc.FONT_REGULAR), size)
    line_gap = int(size * 1.4)
    lines = qc.wrap(draw, sentence, font, W - 2 * MARGIN - 30)
    while len(lines) > 4 and size > 24:
        size -= 3
        font = ImageFont.truetype(str(qc.FONT_REGULAR), size)
        line_gap = int(size * 1.4)
        lines = qc.wrap(draw, sentence, font, W - 2 * MARGIN - 30)
    if len(lines) > 4:
        return None, None

    y = ART_TOP + ART_MAX_H + 52
    box = None
    pattern = re.compile(rf"\b{re.escape(word)}\b", re.I)
    for line in lines:
        line_width = draw.textlength(line, font=font)
        x = (W - line_width) / 2
        draw.text((x, y), line, font=font, fill=INK)
        match = pattern.search(line)
        if match and box is None:
            prefix = draw.textlength(line[:match.start()], font=font)
            width = draw.textlength(match.group(0), font=font)
            ascent, descent = font.getmetrics()
            box = (int(x + prefix), int(y), int(width), int(ascent + descent))
        y += line_gap

    caption_font = ImageFont.truetype(str(qc.FONT_ITALIC), 24)
    credit = f"{painter} · quoted from the classics"
    credit_width = draw.textlength(credit, font=caption_font)
    draw.text(((W - credit_width) / 2, H - 74), credit, font=caption_font, fill=FADE)

    # Photograph the page: soften ink, tilt slightly on a dark cloth
    # backdrop with a cast shadow and a gentle vignette.
    import math
    page = img.filter(ImageFilter.GaussianBlur(0.3)).convert("RGBA")
    angle = (-1.2, 0.9, -0.6, 1.3)[index % 4]
    rotated = page.rotate(angle, resample=Image.BICUBIC, expand=True)

    backdrop = Image.new("RGB", (W, H), "#332e28")
    grad = Image.new("L", (1, H))
    for yy in range(H):
        grad.putpixel((0, yy), int(24 * yy / H))
    backdrop = Image.composite(
        Image.new("RGB", (W, H), "#221e1a"), backdrop, grad.resize((W, H)))

    scale = min((W - 36) / rotated.width, (H - 36) / rotated.height)
    fitted = rotated.resize((int(rotated.width * scale), int(rotated.height * scale)),
                            Image.LANCZOS)
    px = (W - fitted.width) // 2
    py = (H - fitted.height) // 2
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rectangle([px + 10, py + 14, px + fitted.width + 10, py + fitted.height + 14],
                          fill=(0, 0, 0, 110))
    backdrop = Image.alpha_composite(backdrop.convert("RGBA"),
                                     shadow.filter(ImageFilter.GaussianBlur(9)))
    backdrop.paste(fitted, (px, py), fitted)
    final = backdrop.convert("RGB")

    # vignette
    mask = Image.new("L", (W, H), 0)
    md = ImageDraw.Draw(mask)
    md.ellipse([-W * 0.35, -H * 0.35, W * 1.35, H * 1.35], fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(120)).point(lambda v: 255 - v)
    final = Image.composite(final.point(lambda v: max(0, v - 26)), final, mask)

    # transform the word box through the same rotate+scale+offset
    if box is None:
        return None, None
    cx, cy = W / 2, H / 2
    rad = math.radians(-angle)
    ox = (rotated.width - W) / 2
    oy = (rotated.height - H) / 2
    corners = []
    for dx in (0, box[2]):
        for dy in (0, box[3]):
            x0, y0 = box[0] + dx - cx, box[1] + dy - cy
            rx = x0 * math.cos(rad) - y0 * math.sin(rad) + cx + ox
            ry = x0 * math.sin(rad) + y0 * math.cos(rad) + cy + oy
            corners.append((rx * scale + px, ry * scale + py))
    xs = [c[0] for c in corners]
    ys = [c[1] for c in corners]
    final_box = (int(min(xs)), int(min(ys)),
                 int(max(xs) - min(xs)), int(max(ys) - min(ys)))
    return final, final_box


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", type=int, default=100)
    args = parser.parse_args()

    dictionary = bp.Dict()
    words = []
    seen = set()
    for word in wf.USER_WORDS + wf.SAT_CLASSICS:
        lower = word.lower()
        if lower not in seen and dictionary.lookup(lower):
            seen.add(lower)
            words.append(lower)

    print("loading classics…", flush=True)
    corpora = []
    for book in qc.BOOKS:
        text = qc.strip_gutenberg(qc.fetch_book(book[0]))
        if len(text) > 10000:
            corpora.append((book, re.sub(r"\s+", " ", text)))

    wanted = set(words)
    index = {}
    for book, flat in corpora:
        for raw in re.split(r"(?<=[.!?]) ", flat):
            sentence = re.sub(r"^[^A-Z“\"']+", "", raw.strip())
            if not (55 <= len(sentence) <= 160):
                continue
            if sentence.count('"') % 2 or "_" in sentence or "CHAPTER" in sentence:
                continue
            for token in set(re.findall(r"[A-Za-z]+", sentence)):
                lower = token.lower()
                if lower in wanted:
                    index.setdefault(lower, []).append((book, sentence))
    print(f"sentence index covers {len(index)} words", flush=True)

    print("harvesting paintings…", flush=True)
    paintings = harvest_paintings()
    random.Random(3).shuffle(paintings)
    print(f"{len(paintings)} paintings pooled", flush=True)
    urls = bp.thumb_urls([t for _, t in paintings])

    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    for old in PREVIEW_DIR.glob("*.jpg"):
        old.unlink()

    progress_path = REPO / "Data" / "tools" / "promo_progress.json"
    slides, used_books = [], {}
    attempted = 0
    painting_iter = iter(paintings)
    for word in words:
        if len(slides) >= args.target:
            break
        attempted += 1
        candidates = index.get(word, [])
        if not candidates:
            continue
        candidates = sorted(candidates, key=lambda c: (used_books.get(c[0][0], 0), len(c[1])))
        book, sentence = candidates[0]

        art_img, painter = None, None
        while art_img is None:
            try:
                painter_name, title = next(painting_iter)
            except StopIteration:
                break
            url = urls.get(title)
            if not url:
                continue
            try:
                data = bp.fetch_thumb(url)
                candidate = Image.open(io.BytesIO(data)).convert("RGB")
                if candidate.width < 500 or candidate.height < 350:
                    continue
                art_img, painter = candidate, painter_name
            except Exception:
                continue
        if art_img is None:
            print("painting pool exhausted", flush=True)
            break

        card, box = compose(art_img, painter, sentence, word, len(slides))
        if card is None or box is None:
            continue
        used_books[book[0]] = used_books.get(book[0], 0) + 1
        norm = (box[0] / W, box[1] / H, box[2] / W, box[3] / H)
        slides.append({
            "title": f"{painter} · {book[1]} ({book[2]})",
            "word": word, "conf": 100.0, "image": card, "box": norm,
        })
        preview = card.copy()
        preview.thumbnail((300, 400))
        preview.save(PREVIEW_DIR / f"{len(slides):03d}-{word}.jpg", "JPEG", quality=70)
        progress_path.write_text(json.dumps({
            "processed": attempted, "queued": len(words),
            "accepted": len(slides), "target": args.target,
            "words": [s["word"] for s in slides],
        }, ensure_ascii=False))
        print(f"  [{len(slides):3d}] {word:<16} {painter[:20]:<20} {book[1][:26]}", flush=True)

    print(f"Accepted {len(slides)} plates; writing assets…", flush=True)
    bp.write_assets(slides)
    manifest = [{k: s[k] for k in ("title", "word", "conf", "box")} for s in slides]
    (REPO / "Data" / "tools" / "promo_manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False))
    print("Done.", flush=True)


if __name__ == "__main__":
    main()
