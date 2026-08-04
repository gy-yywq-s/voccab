# Voccab — Original App Specification (from reference videos)

Source: two screen recordings (light-mode walkthrough 79s, darkmode.mp4 74s).
Original app version 1.2.3. iPhone, portrait only observed. No tab bar — single
NavigationStack from Home.

## Page inventory & function zoning

### 1. Home (root)
- Background: white; top-left organic light-green "blob" shape bleeding off
  screen edges (irregular rounded organic form, two overlapping green tones
  ~#D6EFD0/#C9EAC4 at varying opacity).
- Top-right: gear icon (Settings push).
- Greeting: cursive script "hi," (large, black, handwriting font ~56pt) + 😄 emoji.
- Stats sentence (bold-ish body, black): "You've learned 6 new words and
  reviewed 35 today. Excellent work! Keep going!"
- Card "My Words" (white/translucent rounded ~24pt, subtle shadow):
  - Left: caption gray "Add New Words Now! >" above bold title "My Words".
  - Right column separated by thin vertical divider: book icon + small "List"
    label. (Whole card → My Words list page.)
- Word-list tile: green rounded square (~120pt, #6FDD8B-ish), bold black
  title truncated "SAT RW..." + gray subtitle "442 words". → list page.
- Promo section: body text "Snap up new words with your camera! Just tap the
  camera button to start." + tall rounded screenshot image (cat photo) showing
  in-photo word overlay card: dark translucent card "hello /hə'ləʊ/ 🔊
  interj. 喂, 嘿" with rows "🔍 单词详情" "+ 与这个照片关联", callout arrow
  pointing at camera button.
- Bottom floating bar (fixed, above home indicator, blur/translucent strip):
  - Search field: capsule, gray placeholder "Lookup words or sentences",
    trailing paste icon in lighter blue circle.
  - Camera button: circle, light-blue fill, blue camera glyph.

### 2. Word list page (e.g. "SAT RW Vocab (442)", also "My Words")
- Large title = list name + count "(442)". Nav bar: < Back, ✓-circle button
  (batch familiarity mark mode?), ⋯ ellipsis-circle menu.
- Pull down reveals Search bar under title.
- Sort chip row (horizontal scroll): [↑ Frequency ▾] [Familiarity] [Planned Review]
  - Active chip: light-blue fill, blue text, ↑ direction arrow, separate ▾
    dropdown section.
  - Frequency dropdown: Show All / Core (1-5000) / High (5000-10000) /
    Medium (10000-20000) / Low (>=20000).
  - Familiarity dropdown: Show All / Familiar (>=80%) / Not Familiar (<80%) / Unknown.
  - Planned Review has direction toggle too.
- Grouped plain list, section headers by sort key:
  - Frequency: "TOP 100", "TOP 1K", "1K-2K", ... word rows sorted by frequency
    band; unknown-band words listed alphabetically (observed alphabetical run).
  - Familiarity: "10%", ... (alphabetical within group)
  - Planned Review: "4 days ago", ... (relative dates)
- Rows: plain white, word text left, chevron right, thin separators.
- Bottom fixed CTA: capsule light-green button, green text+trophy icon
  "Study Current Words" (starts study session for the filtered/current words).

### 3. Word detail page
- Nav: < Back, title = word, [✓-circle if from list context], ⋯ menu.
- Header card (light gray #EEE fill, rounded ~16, full width):
  - Word in large serif bold (New York-ish ~40pt) + top-right ⊕ (add to
    My Words; turns to green ✓ when added; tapping again → context menu
    "Delete from My Words ⊖" red).
  - IPA "/sʌm/" + blue speaker icon (TTS).
  - POS lines: "pron. 一些, 一部分, 若干" / "adv. 大约" / "a. 一些的,..."
  - Note block: darker gray band inside card: "Note: 特别义: certain, 如
    some people = certain people" (user-editable via ⋯ > Edit note).
  - Tag chips row: [Familiarity: 20%] brown/orange fill white text ·
    [Frequency: TOP 100] green fill · [ZK&1+] blue fill · [SAT RW Vocab / My
    Words&1+] tan fill. Right: ?-circle gray button toggles study-info panel.
  - Study-info panel (appears below card when ? tapped):
    - "Set Familiarity:" slider 0–100% with tick marks (20% steps), value label right.
    - Gray caption lines: "You have studied this word 2 times." / "Last
      studied: 3 hours ago" / "Next planned study: in 1 day" / "Memory: Circle 2"
- Segmented control (3): Related | Oxford | English definition.
  - Related: sections like "Base Form" with word chips (light-blue capsule,
    blue text, e.g. "an"→ tappable to that word).
  - Oxford: rich licensed bilingual entry: "some | BrE sʌm,s(ə)m, AmE səm |",
    "A. determiner", numbered senses ① ② with EN gloss + 中文, ▸ example lines
    EN + 中文 translation. (Licensed content — provider must be pluggable/placeholder.)
  - English definition: EN-only entry: word + /IPA/, POS headers (adverb,
    pronoun...), numbered senses, e.g. "Of a measurement: approximately, roughly."
- ⋯ menu items: "Edit note ✎", submenu "Feel Familiar? ✎": 100% Proficient (flag icon) /
  80% Familiar (✓) / 60% Partially (clock) / 40% Somewhat (?) / 0% Unknown (✕).

### 4. Settings
- Grouped list, secondary gray bg, white rows, blue leading icons:
  - WORD LIST: Import Words >
  - WORD: Pronunciation [American ▾] (menu: American/British)
  - STUDY: Daily Goal [New 15 Review 30 ▾]; Target Familiarity [>=90% ▾]
  - ABOUT: Version 1.2.3
- Push transition from Home gear.

### 5. Import Words
- Large title "Import Words", back "< Settings".
- Caption: "Import words from a csv file, this file contains these columns:
  word, note (optional)." with example table image (word/note rows of phrasal verbs).
- Bottom capsule button "Import" (light blue fill, blue text) → file picker.

### 6. My Words (empty state)
- Large title "My Words". Center: 🧐 emoji large + two lines: "This word list
  is empty." / "Search words or pick words from a picture!"

### 7. Study session flow (from dark video)
- Session start page (push from list "Study Current Words"): back label "< SAT
  RW Vocab (375)". Centered: 📖 emoji large, serif title = list name, message
  "Great job! You've mastered 60 new words and reviewed 8 words. Challenge
  yourself with a new set! ⓘ". "Start with:" bold centered. Three option cards
  (full-width rounded rect, secondary fill): left bold big label Mix / All New /
  All Review; right two gray lines "New Words: 15 / Review Words: 0". Disabled
  card dimmed when 0 words (All Review).
- Flashcard: black bg, dimmed underlying page visible. Gray caption "New Word"
  above card. Card: dark gray rounded, centered big serif word + IPA + blue
  speaker. Bottom fixed: thin light-blue progress bar (full-width line) above
  two capsule buttons: "? I Don't Know" (dark red fill, red text+icon) and
  "✓ I Know" (dark green fill, green text+icon).
- (Reveal state not captured in video — design freely: after answer, show CN
  defs + note + tags; advance to next.)
- Leaving mid-session: list bottom bar becomes blue "🏆 Continue Study" capsule
  + separate round ⋯ button (menu presumably: restart/end session).
- Word list ⋯ menu: "Show Archived"/"Hide Archived" (toggle), "Edit name",
  "Delete" (red). So lists support archiving words, rename, delete.

### 8. Search overlay (bottom bar tap)
- Full-screen overlay over dimmed blurred bg, X close top-right.
- Idle: "Searchs in last 7 days" [sic, original typo] header + history rows
  (term left, "23 minutes ago" right, gray).
- Typing: live preview card at top (word header card: serif word, ⊕, IPA +
  speaker, CN defs, tags row [Familiarity: ?] gray [Frequency: >30K] green
  [+ Word lists] brown, ?-circle) + suggestion chips row directly above input
  (gray capsules: similar words e.g. corsage/corkage/wordage/cordages).
- Search field stays at bottom above keyboard; tap preview card → full word
  detail page (nav title = word).
- Unknown-frequency words show "Frequency: ?"; low-frequency ">30K".
- Words not in any list show "+ Word lists" chip (tap → add).
- Word detail supports horizontal swipe paging between words (e.g. plural
  form "indicatives" → its own page, Related shows Base Form chip
  "indicative").

### 9. Settings expansion details
- Daily Goal row expands inline: preset chips [Default] [More New] [More
  Review] + two inline wheel pickers (New: 0/5/10/15..., Review: 15/20/25...).
- Target Familiarity row expands similarly (>=90% etc.).
- Dark mode: standard grouped dark appearance; green tile #2E8B44-ish; blob
  dark forest green (~#2B4226 over black).

## Known data/behavior model
- Word fields: headword, IPA (Am/Br), POS-tagged CN definitions, note,
  familiarity % (0/20/40/60/80/100... slider 20% steps but menu 0/40/60/80/100),
  frequency rank + band (TOP 100/1K/2K.../Core-High-Medium-Low), exam tags
  (ZK&1+ = 中考&1+?, SAT RW Vocab), list memberships (My Words, imported lists),
  studied count, last studied at, next planned study at, memory circle number
  (SRS stage).
- Lists: name, word count, color tile. "My Words" is built-in favorites; CSV
  imports create lists (list name presumably from file).
- Study scheduler: daily goal (new/review counts), target familiarity,
  planned-review dates from SRS circles.
- Pronunciation: TTS or bundled audio, Am/Br setting.
- Lookup: search words or sentences (bottom bar), camera OCR word pick,
  photo-word association.

## User's pain points / requested upgrades
- CANNOT set vocab recitation order in study session → add configurable study
  order (e.g. frequency / familiarity / planned review / alphabetical / random
  / list order, asc/desc) in Settings + per-session override.
- Multi-dictionary support with per-dictionary visibility toggles in Settings
  (English monolingual, English-Chinese, synonyms/thesaurus — like Apple's
  built-in dictionary set). Licensed (Oxford) provider = replaceable placeholder;
  bundle open data: ECDICT (EN→CN), WordNet/Open English WordNet (EN defs +
  synonyms).
