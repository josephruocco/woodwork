# Bookshelf Widget — handoff brief

Paste this whole file into ChatGPT. It describes what exists, then the specific
art task (photorealistic spines via DALL·E) at the end.

---

## What this is

An iOS home screen widget that renders a random handful of the owner's ebook
library as physical books on a wooden shelf. The point is serendipity: 920 books
is far too many to browse, so the widget surfaces ~10 at a time and refreshes
hourly, to nudge you toward something you forgot you owned.

Three targets in one Xcode project (`Bookshelf.xcodeproj`):

| Target | Platform | Job |
|---|---|---|
| `BookshelfScanner` | macOS | Reads the local library, resolves page counts, exports `books.json` |
| `Bookshelf` | iOS | Host app; imports `books.json` into an App Group |
| `BookshelfWidgetExtension` | iOS | The widget itself |

`Shared/Book.swift` and `Shared/ShelfView.swift` are compiled into all three, so
the Mac app previews exactly what the phone will draw.

## Where the data comes from

Neither Apple Books nor Kindle has a public library API, so the Mac app reads the
local databases directly:

- Apple Books — `~/Library/Containers/com.apple.iBooksX/Data/Documents/BKLibrary/BKLibrary-*.sqlite`,
  table `ZBKLIBRARYASSET`. Filter `ZCONTENTTYPE = 1`; type 5 rows are series
  containers ("Incerto"), not books.
- Kindle — `~/Library/Containers/com.amazon.Lassen/Data/Library/Protected/BookData.sqlite`,
  table `ZBOOK`. Empty unless books are downloaded to the Mac.

Both are copied to a temp file before reading, because both apps keep a hot WAL.

## Page count drives spine thickness

This is the detail that makes the shelf read as real, and it took the most work.

`ZPAGECOUNT` exists in the Apple Books schema but is almost never populated — 26
of 920 rows on the reference library. File size is **not** a usable proxy: the
measured spread is 2.1 KB/page for *Anna Karenina* against 41 KB/page for an
illustrated fitness book, because images dominate the EPUB. It was tried and
discarded.

So the scanner enriches from the Open Library search API:

```
https://openlibrary.org/search.json?title=<t>&author=<a>&fields=number_of_pages_median&limit=1
```

`number_of_pages_median` is the right field — it's the median across all editions,
so it doesn't swing on one odd large-print printing. It resolved 523 of the 894
unknowns, taking the library to 549/920 real counts. Results are bounded to 50–4000 pages
and cached on disk, so a rescan is instant. Anything still unknown falls back to
the library's own median (288) and is flagged `pagesEstimated`.

Thickness mapping, in `Book.spineWidth`: `pages × 0.075 pt`, clamped to 9–44 pt.
A 300-page paperback is 22 pt; a 1500-page manual is capped so it can't eat the
shelf.

## How the shelf is drawn

`ShelfView` lays out rows to fit whatever height it's given, so one view serves
the small, medium and large widget families.

A row is a list of `ShelfItem`s — `.upright`, `.leaning`, or `.stack` (books lying
flat in a pile). Layout deliberately leaves 16–30 pt of slack about 70% of the
time, because a shelf packed wall-to-wall gives the last book nothing to lean
into. Flat piles only appear when the row is at least 240 pt wide, so small
widgets never get one. A leaning book's footprint is computed as
`w·cos θ + h·sin θ` at θ = 9°, not its spine width, or the row silently overflows.

Everything visual is derived from a **stable FNV-1a hash of the book id** — colour,
height variation, pile membership. Swift's built-in `Hasher` is seeded per
process and would reshuffle every spine's colour on each widget launch. Book
selection uses a SplitMix64 seeded by the hour, so the shelf is stable within an
hour and fresh on the next.

`Tests/main.swift` is a runnable assert-based check of the thickness and packing
logic:

```
swiftc -o /tmp/check Shared/Book.swift Shared/ShelfView.swift Tests/main.swift && /tmp/check
```

---

# The art task: photorealistic spines with DALL·E

Currently each spine is drawn procedurally — a linear gradient in one of 14 muted
cloth colours, two gilt rules, and the title set vertically in a serif. It reads
clearly as books, but it's flat vector art, not photography.

## The constraint that shapes the whole approach

**Do not ask DALL·E to generate book spines with the titles on them.** Two reasons:

1. There are 920 books, and the set changes whenever the owner buys one. Per-book
   generation doesn't scale and can't cover new arrivals.
2. Diffusion models still render long text unreliably. A spine reading
   "PROFFESSOR BORGEES" ruins the effect completely, and it would be wrong in a
   different way in every image.

**Generate blank spine *materials*, keep the titles as live text.** The app already
draws crisp, correct, correctly-sized titles in SwiftUI. Photography supplies the
grain, weave, wear and lighting that vector fills can't; the text layer stays
sharp and truthful. This is also how the thickness data keeps working — a texture
is stretched to whatever width the page count dictates.

## What to generate

**12 spine material textures**, no text, no titles, no lettering of any kind.

Each: a straight-on, perfectly flat photograph of a single blank book spine,
filling the frame, shot square to the camera with no perspective. Even, soft,
diffuse lighting — no hotspots, no cast shadows, no background visible. The app
applies its own lighting gradient and drop shadow on top, so baked-in lighting
will fight it and look wrong.

Cover these materials:

1. Worn dark green buckram cloth
2. Oxblood leather, fine grain
3. Cream linen, slightly foxed with age
4. Navy blue cloth, tight weave
5. Black pebbled leather
6. Faded mustard/ochre cloth
7. Deep burgundy leather, smooth
8. Slate grey cloth, coarse weave
9. Tan calfskin
10. Dark teal cloth, sun-faded along one edge
11. Charcoal cloth, lightly scuffed
12. Aged parchment paperback stock

### Prompt to use (substitute the material each time)

> A macro photograph of the blank spine of an old hardcover book, made of **worn
> dark green buckram cloth**. Straight-on flat view, perfectly square to the
> camera, no perspective or angle. The spine fills the entire frame vertically.
> Completely blank — no text, no lettering, no title, no author, no logos, no
> decoration of any kind. Even soft diffuse studio lighting with no highlights or
> shadows. Sharp focus on the fabric weave and grain. Neutral colour balance.
> Photorealistic, high detail.

If lettering still appears, add: *"the spine is entirely bare and unprinted, an
unfinished book cover with no markings"* — and regenerate rather than trying to
retouch.

### Output spec

- Square generations are fine; **crop to a tall strip, roughly 1:8 (e.g. 160 × 1280 px)**.
  Crop from the centre so the weave stays uniform.
- The top and bottom ~10% get covered by the app's gilt rules, so those regions
  don't need to be interesting.
- Save as PNG: `spine-01.png` … `spine-12.png`.
- Keep them under ~200 KB each. Widget extensions have a tight memory budget and
  will be killed if the asset catalogue is heavy.
- The texture must tolerate vertical stretching, since spine height varies 84–100%
  of the row. Avoid anything with a strong repeating horizontal pattern.

## How they get used in the app

In `Shared/ShelfView.swift`, `ItemView.face(_:length:vertical:)` currently fills
the spine with a `LinearGradient`. Replace that fill with the texture, tinted by
the existing palette colour:

```swift
Image("spine-\(book.textureIndex)")
    .resizable()
    .aspectRatio(contentMode: .fill)
    .colorMultiply(base)          // existing cloth colour still drives variety
    .overlay(LinearGradient(       // keep this — it's the shelf's lighting
        colors: [.white.opacity(0.10), .clear, .black.opacity(0.28)],
        startPoint: .leading, endPoint: .trailing))
```

Add `textureIndex` to `Book` alongside `cloth`, derived from the same stable hash
(`stableHash(3) % 12`). 12 textures × 14 tint colours gives 168 distinct looks
across ~10 visible books — repeats will effectively never be noticed.

For books lying flat in a pile, pass the same image with
`.rotationEffect(.degrees(90))` before it's resized; the `vertical` flag in
`face()` already distinguishes the two cases.

## Worth doing at the same time

A single photorealistic **empty shelf plate** would lift the result more than the
spines do, for one image instead of twelve. Replace the `Backdrop` and `Board`
views with it:

> A photograph of an empty dark walnut bookshelf, straight-on flat view, square
> to the camera. One horizontal shelf board across the bottom, bare wood, warm
> tone, visible grain. Soft even lighting, deep shadow in the empty cavity above
> the board. No books, no objects. Photorealistic.

Generate it wide (roughly 3:1) and slice one row's worth; `ShelfView` tiles rows
vertically, so a single row plate repeats cleanly.

## Please don't change

- Titles stay live SwiftUI text. Don't move them into generated images.
- Spine width must stay driven by `Book.spineWidth`. It's the whole conceit that
  a 1000-page book looks like a 1000-page book, and it's the part that took real
  work to get accurate data for.
- Colour and height must stay derived from the stable FNV-1a hash, never
  `Hasher` or `Int.random()` without a seed, or the shelf flickers between
  renders.
