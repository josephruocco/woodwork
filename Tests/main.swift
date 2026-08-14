// Self-check for the two bits of real logic: spine thickness and shelf packing.
//   swiftc -o /tmp/check Shared/Book.swift Shared/ShelfView.swift Tests/main.swift && /tmp/check
import Foundation

func book(_ title: String, _ pages: Int) -> Book {
    Book(id: title, title: title, author: "A", pages: pages, pagesEstimated: false)
}

// Thickness follows page count, and clamps so nothing vanishes or eats the shelf.
assert(book("a", 200).spineWidth < book("b", 600).spineWidth)
assert(book("tiny", 1).spineWidth >= 9)
assert(book("huge", 99_999).spineWidth <= 44)
assert(book("x", 300).spineWidth == book("y", 300).spineWidth)

// Colour and height must be stable across processes — FNV-1a, not Swift's
// per-process-seeded Hasher.
assert(fnv1a("Moby-Dick") == 10_498_371_713_199_089_330)

let width: CGFloat = 320
let spineHeight: CGFloat = 106
let library = (0..<200).map { book("Book \($0)", 100 + $0 * 7) }
let shelves = ShelfView.layout(library, rows: 3, width: width, spineHeight: spineHeight)

assert(shelves.count == 3)
for shelf in shelves {
    assert(!shelf.isEmpty)
    // Leaning books and flat piles must be measured by their real footprint,
    // not their spine width, or a row silently overflows the shelf.
    let used = shelf.reduce(0) { $0 + $1.footprint(spineHeight: spineHeight) + 1.5 }
    assert(used <= width, "row overflows the shelf: \(used)")
    assert(used > width - 40, "row leaves a visible gap: \(width - used)pt")
    let ids = shelf.flatMap(\.books).map(\.id)
    assert(Set(ids).count == ids.count, "same book twice in one row")
}
// Rows draw from distinct stock.
let firstIDs = Set(shelves[0].flatMap(\.books).map(\.id))
assert(firstIDs.isDisjoint(with: Set(shelves[1].flatMap(\.books).map(\.id))))

// A library too small to stock every shelf repeats instead of leaving rows bare.
let tiny = (0..<4).map { book("Small \($0)", 300) }
assert(ShelfView.layout(tiny, rows: 3, width: width, spineHeight: spineHeight)
    .allSatisfy { !$0.isEmpty })

// Same seed, same shelf — WidgetKit re-renders an entry and must not reshuffle.
assert(ShelfView.layout(library, rows: 2, width: width, spineHeight: spineHeight).map(\.ids)
    == ShelfView.layout(library, rows: 2, width: width, spineHeight: spineHeight).map(\.ids))

// Widget shelf slots cycle through three stable arrangements.
assert(ShelfLayoutVariant.forShelf(1) == .balanced)
assert(ShelfLayoutVariant.forShelf(2) == .stacked)
assert(ShelfLayoutVariant.forShelf(3) == .gallery)
assert(ShelfLayoutVariant.forShelf(4) == .balanced)
let variants = ShelfLayoutVariant.allCases.map {
    ShelfView.layout(library, rows: 2, width: width, spineHeight: spineHeight, variant: $0).map(\.ids)
}
assert(Set(variants.map { $0.description }).count == variants.count,
       "layout variants should produce distinct shelf arrangements")

let fixedHour = Date(timeIntervalSince1970: 1_800_000_000)
let widgetShelfOne = Book.onWidgetShelf(library, shelf: 1, at: fixedHour)
assert(widgetShelfOne == Book.onWidgetShelf(library, shelf: 1, at: fixedHour))
assert(widgetShelfOne != Book.onWidgetShelf(library, shelf: 2, at: fixedHour),
       "different widget shelves should display different books")

// A small widget is too narrow for a flat pile.
let narrow = ShelfView.layout(library, rows: 1, width: 150, spineHeight: 90)[0]
assert(!narrow.contains { if case .stack = $0 { true } else { false } })

extension Array where Element == ShelfItem {
    var ids: [String] { map(\.id) }
}

print("ok")
