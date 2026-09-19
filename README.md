# WoodWork

An iPhone home screen widget that draws your ebook library as a real bookshelf —
**spine thickness set by each book's actual page count**. Its rediscovery mode
remembers what each shelf has shown, then brings overlooked books back into view.
Pulling them out of the woodwork.

Tap the widget and the app lists exactly what's currently on the shelf; tap a
title and it opens in Apple Books or Kindle.

## What's in here

| Target | Platform | Job |
|---|---|---|
| `BookshelfScanner` | macOS | Reads the local library, resolves page counts, exports `books.json` |
| `Bookshelf` | iOS | Host app: per-shelf discovery and theme controls, current shelf list, library import |
| `BookshelfWidgetExtension` | iOS | The widget — small, medium and large |

`Shared/` is compiled into all three, so the Mac app previews exactly what the
phone draws. Target names still say Bookshelf; only the display name is
WoodWork, because renaming bundle IDs would orphan the App Group and the
page-count cache for no visible gain.

## Where the data comes from

WoodWork supports three import paths. The iPhone app can sync directly from a
running Calibre Content Server, receive the Mac scanner's library over iCloud,
or import a `books.json` file manually. These are alternatives; adding Calibre
does not remove either existing option.

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

### Calibre Content Server

1. In Calibre choose **Connect/share → Start Content Server**.
2. In the iPhone app open **Calibre Content Server** and select the server found
   on your network. If discovery is unavailable, enter the address Calibre shows
   (for example `http://192.168.1.2:8080`).
3. Tap **Test Connection**, select a library if the server exposes more than one,
   then tap **Connect and Sync**.
4. Keep the iPhone and the computer running Calibre on the same network.

The app imports titles, authors and Calibre's page metadata into the same shared
library used by the widget. Tapping a Calibre title opens its page on the Content
Server. Optional HTTP Basic Authentication is supported; passwords are stored in
the iOS Keychain and never placed in the shared widget data.

### Mac scanner or JSON file

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

## Calibre release material

- [`Launch/CalibreAdoption.md`](Launch/CalibreAdoption.md) — positioning,
  distribution sequence, trust rules, and adoption targets.
- [`Launch/MobileReadBetaPost.md`](Launch/MobileReadBetaPost.md) — prepared beta
  announcement for the Calibre Plugins forum.
- [`Launch/CalibreTestMatrix.md`](Launch/CalibreTestMatrix.md) — compatibility
  gates for plugin-index submission and iPhone Content Server support.
