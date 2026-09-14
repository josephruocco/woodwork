# WoodWork Shelf for calibre

WoodWork Shelf adds a **Reshuffle Shelf** action to calibre 7 or newer. It
replaces the current view with a fresh random subset while leaving book files
and metadata untouched.

## Install

1. Download `WoodWorkShelf.zip`.
2. In calibre, open **Preferences → Plugins → Load plugin from file**.
3. Select the ZIP and restart calibre.
4. Add **Reshuffle Shelf** to a toolbar from **Preferences → Toolbars & menus**.

Click the main action to draw a new 60-book shelf. Its menu lets you choose 24,
36, 60, or 90 books and restore the exact search that was visible beforehand.
The current search or Virtual Library becomes the candidate pool, so WoodWork
can reshuffle a filtered collection such as unread fiction rather than the
entire library. Your shelf-size choice is remembered between calibre sessions.

## What it is—and is not

calibre already includes **Pick a random book**. WoodWork Shelf does something
different: it creates a browsable random shortlist from the view you have
already filtered. Keep clicking **Reshuffle Shelf** until a shelf catches your
attention, then open any book normally.

The plugin is local-only, contains no analytics, and never changes your library.
The optional WoodWork iPhone app can separately sync from calibre's Content
Server and display a rotating shelf as a Home Screen widget.

## Release history

- **1.1.0:** Remember shelf size, show the selected size, add restore state and
  help links, and support calibre 7 or newer.
- **1.0.0:** Initial reshuffle action with current-view and Virtual Library
  support.
