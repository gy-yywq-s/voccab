#!/usr/bin/env python3
"""Word-first gallery builder: pick SAT-hard words, then SEARCH Commons for
artistic material containing each word (LOC/NARA file titles quote the
artwork's own text), verify by OCR, crop, emit assets.

Inverts build_promo.py's image-first funnel (~1% yield) into a targeted
search (~30%+ yield). Reuses its caches, OCR, cropping and asset writer.
"""
import argparse
import concurrent.futures as futures
import io
import json
import random
import re
import sys
import tempfile
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_promo as bp

REPO = bp.REPO
PREVIEW_DIR = REPO / "Data" / "tools" / "preview"

# The user's own SAT list (single words only) — first priority.
USER_WORDS = """pristine visionary conflate epitomize lambaste subvert presage palpable
spurious peculiar grotesque tranquil noxious superfluous commonplace mischievous
quintessential embellish imposing unassuming shrewd scrutinize scrupulous interpolate
extrapolate convene brood construe misconstrue prohibitive strive arcane ubiquity
defunct excise illuminate multitude recant proclaim dearth preponderance intermittent
supplant transpose profuse frailty sustenance denounce renounce forsake assuage convey
minutiae oversee oversight obscure intrigue conceive behold beholden repudiate efface
eschew imposter posture pervasive prevail exorbitant intersperse perky ecstatic
canonical tentative contentious aspersion""".split()

# Classic SAT/GRE-band vocabulary — the difficulty standard the gallery targets.
SAT_CLASSICS = """abate abhor abject abjure abstruse accolade acrimony acumen admonish
adroit adulation alacrity altruism ambivalent ameliorate amiable anachronism animosity
apathy aplomb apocryphal ardent arduous ascetic assiduous astute audacious austere
avarice banal bellicose benevolent benign bolster bombastic brazen brevity cacophony
cajole calamity candor capitulate capricious castigate caustic censure chastise
circuitous circumspect clemency cogent complacent conciliatory condone conflagration
confluence congenial consecrate consternation contrite conundrum copious cordial
corroborate covet credulous cryptic culpable cursory dauntless debacle debilitate
decorous deference deleterious deluge demure denigrate deplete despondent destitute
desultory diaphanous diatribe didactic diffident diligent discern disdain disparage
disparate disseminate dissonance divergent docile dogmatic dubious duplicity ebullient
eclectic edifice efficacious egregious eloquent elucidate elusive empathy emulate
enervate engender enigma enmity ephemeral equanimity equivocal erudite esoteric
ethereal eulogy evanescent exacerbate exasperate exemplary exonerate expedient extol
exuberant facetious fallacious fastidious fathom fecund felicity fervent fickle
flagrant florid foment forbearance forlorn fortitude fortuitous fractious frugal
furtive garrulous gregarious guile hackneyed hapless harbinger haughty hedonist
hegemony heresy hiatus hubris iconoclast idiosyncrasy immutable impasse imperious
impetuous implacable incessant indefatigable indelible indigent indolent ineffable
inexorable ingenuous inimical iniquity innocuous inscrutable insidious insipid
intransigent intrepid inundate invective irascible itinerant jubilant judicious
juxtapose laconic lament languid latent laudable lethargic levity limpid lithe
loquacious lucid lugubrious luminous magnanimous malevolent malleable maudlin maverick
mellifluous mendacious mercurial meticulous mitigate mollify morose mundane munificent
myriad nadir nascent nefarious nonchalant novice obdurate obfuscate oblique oblivion
obsequious obstinate obtuse odious officious opulent ostentatious palliate panacea
paragon pariah parsimony pastoral paucity pejorative penchant pensive perfidious
perfunctory pernicious perspicacious pertinent placate placid platitude plausible
plethora poignant pragmatic precipice preclude predilection presumptuous pretentious
prodigal profligate prosaic protean prudent puerile pugnacious quandary querulous
quiescent rancor rapacious rebuke recalcitrant reclusive redolent refute relegate
relinquish remiss replete reproach rescind resilient resolute reticent reverent
rhetoric rife sagacious salient salubrious sanguine sardonic scintillating serene
serendipity solace solicitous somber soporific spurn squander staid stalwart stoic
strident sublime subtle succinct supercilious surreptitious sycophant taciturn
tantamount tenacious tenuous terse timorous torpid trepidation truculent turbulent
ubiquitous umbrage unctuous undulate untenable upbraid vacillate vapid vehement
venerate veracity verbose vestige vex vicarious vigilant vilify vindicate virtuoso
vitriol vivacious vociferous volatile wanton wary whimsical wistful zealous zenith
zephyr""".split()

ART_TERMS = ('poster OR lithograph OR "sheet music" OR broadside OR "title page" '
             'OR engraving OR woodcut OR advertisement OR illustration OR cover')
TITLE_REJECT = re.compile(
    r"geograph\.org|\bMOD \d|conference|forum|screenshot|logo|meeting|summit|"
    r"HMS |USS |graduation|diploma", re.I)


def search_word(word):
    """Commons fulltext search for artistic bitmaps containing the word."""
    try:
        data = bp.api_get({
            "action": "query", "list": "search", "srnamespace": 6,
            "srlimit": 4,
            "srsearch": f'"{word}" filetype:bitmap ({ART_TERMS})',
        })
    except Exception:
        return []
    titles = [hit["title"] for hit in data.get("query", {}).get("search", [])]
    return [t for t in titles
            if not TITLE_REJECT.search(t)
            and t.lower().endswith((".jpg", ".jpeg", ".png", ".tif", ".tiff"))]


def find_word_box(rows, word):
    """The OCR box for this specific word, best confidence first."""
    best = None
    for text, conf, box in rows:
        clean = re.sub(r"[^A-Za-z]", "", text).lower()
        if clean == word and conf >= 70:
            if best is None or conf > best[0]:
                best = (conf, box)
    return best


def process_word(word):
    """Try to produce one slide for this word."""
    titles = search_word(word)
    if not titles:
        return None
    urls = bp.thumb_urls(titles)
    for title in titles:
        url = urls.get(title)
        if not url:
            continue
        try:
            data = bp.fetch_thumb(url)
            img = Image.open(io.BytesIO(data)).convert("RGB")
        except Exception:
            continue
        import hashlib
        key = hashlib.md5(url.encode()).hexdigest()
        # OCR on a downscaled copy (huge speedup on dense scans), then map
        # the box back to full resolution.
        ocr_img = img.copy()
        ocr_img.thumbnail((700, 900))
        scale = img.width / ocr_img.width
        with tempfile.NamedTemporaryFile(suffix=".png") as tmp:
            ocr_img.save(tmp.name)
            try:
                rows = bp.ocr_words(tmp.name, cache_key=f"{key}-700")
            except Exception:
                continue
        found = find_word_box(rows, word)
        if not found:
            continue
        conf, box = found
        box = tuple(int(v * scale) for v in box)
        result = bp.crop_for_word(img, box)
        if not result:
            continue
        crop, norm = result
        return {"title": title, "word": word, "conf": conf,
                "image": crop, "box": norm}
    return None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", type=int, default=100)
    args = parser.parse_args()

    dictionary = bp.Dict()
    pool = []
    seen = set()
    for word in USER_WORDS + SAT_CLASSICS:
        lower = word.lower()
        if lower in seen or lower in bp.CURATED_OUT:
            continue
        seen.add(lower)
        entry = dictionary.lookup(lower)
        if not entry or not entry["translation"]:
            continue
        pool.append(lower)
    random.Random(7).shuffle(pool)
    # user's words keep priority at the front
    pool.sort(key=lambda w: 0 if w in USER_WORDS else 1)
    print(f"word pool: {len(pool)} SAT-band words", flush=True)

    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    for old in PREVIEW_DIR.glob("*.jpg"):
        old.unlink()

    progress_path = REPO / "Data" / "tools" / "promo_progress.json"
    slides = []
    attempted = [0]

    def write_progress():
        progress_path.write_text(json.dumps({
            "processed": attempted[0], "queued": len(pool),
            "accepted": len(slides), "target": args.target,
            "words": [s["word"] for s in slides],
        }, ensure_ascii=False))

    write_progress()
    with futures.ThreadPoolExecutor(max_workers=6) as executor:
        pending = {executor.submit(process_word, w): w for w in pool}
        for future in futures.as_completed(pending):
            attempted[0] += 1
            if len(slides) >= args.target:
                break
            slide = future.result()
            if not slide:
                if attempted[0] % 10 == 0:
                    write_progress()
                continue
            slides.append(slide)
            preview = slide["image"].copy()
            preview.thumbnail((300, 400))
            preview.save(PREVIEW_DIR / f"{len(slides):03d}-{slide['word']}.jpg",
                         "JPEG", quality=70)
            write_progress()
            print(f"  [{len(slides):3d}] {slide['word']:<16} conf={slide['conf']:.0f}  {slide['title'][:70]}",
                  flush=True)

    slides = slides[:args.target]
    print(f"Accepted {len(slides)} slides; writing assets…", flush=True)
    bp.write_assets(slides)
    manifest = [{k: s[k] for k in ("title", "word", "conf", "box")} for s in slides]
    (REPO / "Data" / "tools" / "promo_manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False))
    write_progress()
    print("Done.", flush=True)


if __name__ == "__main__":
    main()
