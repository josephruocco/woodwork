# WoodWork

An iPhone home screen widget that draws your ebook library as a real bookshelf —
**spine thickness set by each book's actual page count**. It shows a random
handful at a time and reshuffles every hour, so you keep catching sight of books
you forgot you owned. Pulling them out of the woodwork.

Tap the widget and the app lists exactly what's currently on the shelf; tap a
title and it opens in Apple Books or Kindle.

## What's in here

| Target | Platform | Job |
|---|---|---|
| `BookshelfScanner` | macOS | Reads the local library, resolves page counts, exports `books.json` |
| `Bookshelf` | iOS | Host app: theme picker, "On Your Shelf" list, library import |
| `BookshelfWidgetExtension` | iOS | The widget — small, medium and large |

`Shared/` is compiled into all three, so the Mac app previews exactly what the
phone draws. Target names still say Bookshelf; only the display name is
WoodWork, because renaming bundle IDs would orphan the App Group and the
page-count cache for no visible gain.

## Where the data comes from

Neither Apple Books nor Kindle has a public library API, so the Mac app reads the
local databases directly — Apple Books from `BKLibrary-*.sqlite`
(`ZBKLIBRARYASSET`, content type 1; type 5 rows are series containers, not
books), Kindle from `BookData.sqlite` (`ZBOOK`, populated only for books
downloaded to that Mac). Both are copied before reading, because both apps keep a
hot WAL.

## Page counts, which are the whole point

`ZPAGECOUNT` exists but is almost never filled in — 26 of 920 books in the
reference library. File size is **not** a usable proxy: 2.1 KB/page for *Anna
Karenina* against 41 KB/page for an illustrated title, because images dominate
the EPUB. It was tried and discarded.

So the scanner enriches from Open Library's `number_of_pages_median` — the median
across all editions, so one odd large-print printing can't skew it. That took the
library to **549 real page counts**; the rest fall back to the library's own
median and are flagged `pagesEstimated`. Lookups are cached, so a rescan is
instant.

Thickness: `pages × 0.075pt`, clamped 9–44. A 300-page paperback is 22pt; a
1500-page manual is capped so it can't eat the shelf.

## Setup

1. Build and run `BookshelfScanner` on your Mac → **Scan Library** → **Save
   books.json…**. First run takes a few minutes for the page-count lookups.
   macOS will ask permission to read other apps' data; if you decline, use
   **Choose BKLibrary Folder…**.
2. In Xcode set your Development Team on all three targets and change the bundle
   IDs off `com.josephruocco.*`.
3. Run `Bookshelf` on your phone, **Import books.json…**, then long-press the
   home screen → **+** → WoodWork.

`Resources/books.json` is **not** committed — it's a personal reading history, so
it stays out of the repo. The project expects it at build time, so on a fresh
clone start from the sample:

```bash
cp Resources/books.sample.json Resources/books.json
```

Then replace it with your own export from the scanner.

## Notes

- **App Group.** The app hands the library and the theme to the widget through
  `group.com.josephruocco.bookshelf`. If entitlements get stripped from a build,
  `UserDefaults(suiteName:)` silently gives the app and widget *separate* stores
  and the theme stops propagating — that failure is invisible, so check the
  entitlement first when the widget ignores a setting.
- **Deep links.** A widget can't launch another app: WidgetKit routes `Link` URLs
  to the containing app. So taps go through `bookshelf://`, and the app forwards
  to `ibooks://assetid/…` or `kindle://book?action=open&asin=…`.
- **`ArtSource/` is not shipped.** It holds the full-size source images for the
  spine textures; only the cropped `Resources/ThemeAssets/**/final` files go into
  the app. They were once wired into the bundle by accident, which put 74 MB into
  the app and widget.

## Tests

```bash
swiftc -o /tmp/check Shared/Book.swift Shared/ShelfView.swift Tests/main.swift && /tmp/check
```

Covers spine thickness, row packing (leaning books and flat piles measured by
real footprint, not spine width), no repeats within a row, and render stability.
The newer `.featured` item and layout options aren't covered yet.
