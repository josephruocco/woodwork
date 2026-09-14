# MobileRead beta post

## Thread title

`[GUI Plugin] WoodWork Shelf — reshuffle the current view into a random shortlist`

## First post

WoodWork Shelf adds a **Reshuffle Shelf** action to Calibre. It draws a fresh
random shortlist from whatever is currently visible—your whole library, a
search, or a Virtual Library—without changing metadata or book files.

Calibre already has **Pick a random book**. This plugin is intentionally
different: it keeps a browsable set of 24, 36, 60, or 90 books on screen so you
can scan several possibilities instead of accepting a single pick. Repeated
reshuffles continue drawing from the original filtered collection, and
**Restore Previous View** returns to the search you had before.

### Installation

1. Download the attached `WoodWorkShelf.zip`.
2. Open **Preferences → Plugins → Load plugin from file**.
3. Select the ZIP and restart Calibre.
4. Add **Reshuffle Shelf** under **Preferences → Toolbars & menus**.

The main button reshuffles immediately. Its menu changes shelf size or restores
the previous view. The selected size is remembered between sessions.

### Privacy and safety

- No analytics or network requests.
- No metadata or book-file changes.
- The full Python source is inside the ZIP and available at
  `github.com/josephruocco/woodwork`.

### Compatibility

- Declared support: Calibre 7 or newer; macOS, Windows, and Linux.
- Verified so far: Calibre 9.2.1 on macOS.
- This is a beta specifically to verify Calibre 7/8 and Windows/Linux.

If something fails, please include your operating system, Calibre version, what
was filtered before reshuffling, and any error text.

### Optional iPhone companion

WoodWork for iPhone can connect separately to a Calibre Content Server and put
a rotating visual shelf on the Home Screen. The desktop plugin works fully
without the app. Setup and screenshots: `https://getwoodwork.app/calibre/`

### Version history

- **1.1.0:** Remember shelf size, indicate the selected size, improve restore
  state, add help links, and declare Calibre 7+ support.
- **1.0.0:** Initial beta.

