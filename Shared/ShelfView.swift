import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// One position on a shelf. Real shelves aren't all soldiers in a row: books
/// slump into gaps and piles lie flat at the end.
enum ShelfItem: Identifiable {
    case upright(Book)
    case leaning(Book)
    case stack([Book])

    var id: String {
        switch self {
        case .upright(let b): "u-" + b.id
        case .leaning(let b): "l-" + b.id
        case .stack(let bs): "s-" + bs.map(\.id).joined(separator: "+")
        }
    }

    var books: [Book] {
        switch self {
        case .upright(let b), .leaning(let b): [b]
        case .stack(let bs): bs
        }
    }

    /// Shelf width this item eats. A leaning book covers more floor than it
    /// would standing; a flat pile is as wide as the books are tall.
    func footprint(spineHeight: CGFloat) -> CGFloat {
        switch self {
        case .upright(let b):
            b.spineWidth
        case .leaning(let b):
            b.spineWidth * ShelfView.leanCos + flatLength(b, spineHeight) * ShelfView.leanSin
        case .stack(let bs):
            bs.map { flatLength($0, spineHeight) }.max() ?? 0
        }
    }
}

/// A book lying down is as long as it was tall.
private func flatLength(_ book: Book, _ spineHeight: CGFloat) -> CGFloat {
    spineHeight * book.heightFactor
}

/// A wall of shelves, filled from `books` (already shuffled by the caller).
/// Row count follows the height it's given, so the same view serves small,
/// medium and large widgets.
struct ShelfView: View {
    let books: [Book]
    var theme: ShelfTheme = .classic

    private let rowHeight: CGFloat = 118
    private let sideInset: CGFloat = 5

    static let leanDegrees: CGFloat = 9
    static let leanCos = cos(leanDegrees * .pi / 180)
    static let leanSin = sin(leanDegrees * .pi / 180)

    var body: some View {
        GeometryReader { geo in
            let rows = themedRowCount(for: geo.size.height)
            let rowH = geo.size.height / CGFloat(rows)
            let usable = geo.size.width - sideInset * 2
            let spineSpace = rowH - boardThickness - 6
            let shelves = Self.layout(books, rows: rows, width: usable, spineHeight: spineSpace)

            VStack(spacing: 0) {
                ForEach(0..<rows, id: \.self) { row in
                    shelfRow(shelves[row], height: rowH, width: usable, spineSpace: spineSpace)
                }
            }
        }
        .background(Backdrop(theme: theme))
        .overlay { ShelfFrame(theme: theme) }
    }

    private func shelfRow(_ row: [ShelfItem], height: CGFloat, width: CGFloat,
                          spineSpace: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            ShelfPlate(theme: theme)

            HStack(alignment: .bottom, spacing: 1.5) {
                ForEach(row) { item in
                    ItemView(item: item, spineHeight: spineSpace, theme: theme)
                }
                Spacer(minLength: 0)
            }
            .frame(width: width, alignment: .leading)
            .padding(.horizontal, horizontalInset)
            .padding(.bottom, boardThickness)

            Board(thickness: boardThickness, theme: theme)
        }
        .frame(height: height)
        .overlay(alignment: .leading) {
            if theme == .realistic || theme == .walnut {
                ShelfSide(theme: theme, lightOnLeadingSide: true)
                    .frame(width: theme == .walnut ? 10 : 9)
                    .padding(.vertical, 2)
            }
        }
        .overlay(alignment: .trailing) {
            if theme == .realistic || theme == .walnut {
                ShelfSide(theme: theme, lightOnLeadingSide: false)
                    .frame(width: theme == .walnut ? 10 : 9)
                    .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Layout

    static func layout(_ pool: [Book], rows: Int, width: CGFloat,
                       spineHeight: CGFloat) -> [[ShelfItem]] {
        guard !pool.isEmpty else { return Array(repeating: [], count: rows) }
        var unused = pool
        return (0..<rows).map { row in
            // A library too small to stock every shelf repeats rather than
            // leaving rows bare.
            if unused.count < 6 { unused = pool }
            let items = buildRow(unused, width: width, spineHeight: spineHeight, index: UInt64(row))
            let taken = Set(items.flatMap(\.books).map(\.id))
            unused.removeAll { taken.contains($0.id) }
            return items
        }
    }

    private static func buildRow(_ books: [Book], width: CGFloat, spineHeight: CGFloat,
                                 index: UInt64) -> [ShelfItem] {
        var rng = SeededRNG(seed: index &* 7919 &+ fnv1a(books.first?.id ?? ""))
        var pool = books

        // A flat pile needs room for a book on its side plus a few uprights, so
        // small widgets never get one.
        var pile: [ShelfItem] = []
        if width >= 240, Int.random(in: 0..<10, using: &rng) < 5 {
            let count = Int.random(in: 2...4, using: &rng)
            var picked: [Book] = []
            var stackHeight: CGFloat = 0
            for book in pool where picked.count < count {
                guard flatLength(book, spineHeight) < width * 0.55,
                      stackHeight + book.spineWidth < spineHeight * 0.55 else { continue }
                picked.append(book)
                stackHeight += book.spineWidth
            }
            if picked.count >= 2 {
                pile = [.stack(picked)]
                let ids = Set(picked.map(\.id))
                pool.removeAll { ids.contains($0.id) }
            }
        }

        let pileWidth = pile.first?.footprint(spineHeight: spineHeight) ?? 0
        // Leave some slack most of the time: a shelf packed wall-to-wall has
        // nothing for the last book to lean into.
        let wantsLean = Int.random(in: 0..<10, using: &rng) < 7
        let slack: CGFloat = wantsLean ? CGFloat(Int.random(in: 16...30, using: &rng)) : 0
        let standing = bestFit(pool, width: max(0, width - pileWidth - slack - 2), row: index)

        // The book at the open end is the one that slumps.
        var items = standing.map { ShelfItem.upright($0) }
        if wantsLean, items.count >= 2, case .upright(let book) = items[items.count - 1] {
            items[items.count - 1] = .leaning(book)
        }
        return items + pile
    }

    /// Greedy fill, best of a few shuffles: picking the arrangement with the
    /// smallest trailing gap is what keeps the shelf from looking half-empty.
    private static func bestFit(_ books: [Book], width: CGFloat, row: UInt64) -> [Book] {
        guard width > 0 else { return [] }
        var best: [Book] = []
        var bestGap = CGFloat.greatestFiniteMagnitude
        for attempt in 0..<8 {
            var rng = SeededRNG(seed: row &* 1_000 &+ UInt64(attempt) &+ fnv1a(books.first?.id ?? ""))
            var used: CGFloat = 0
            var picked: [Book] = []
            for book in books.shuffled(using: &rng) {
                let next = used + book.spineWidth + 1.5
                if next > width { continue }
                picked.append(book)
                used = next
                if width - used < 10 { break }
            }
            if width - used < bestGap { bestGap = width - used; best = picked }
            if bestGap < 6 { break }
        }
        return best
    }

    private var horizontalInset: CGFloat {
        switch theme {
        case .realistic:
            sideInset + 10
        case .walnut:
            sideInset + 8
        case .classic, .artsy:
            sideInset
        }
    }

    private var boardThickness: CGFloat {
        switch theme {
        case .walnut:
            10
        case .realistic:
            9
        case .classic, .artsy:
            6
        }
    }

    private func themedRowCount(for height: CGFloat) -> Int {
        switch theme {
        case .walnut, .realistic:
            return height >= 250 ? 2 : 1
        case .classic, .artsy:
            return max(1, Int(height / rowHeight))
        }
    }
}

// MARK: - Drawing

private struct ItemView: View {
    let item: ShelfItem
    let spineHeight: CGFloat
    let theme: ShelfTheme

    var body: some View {
        switch item {
        case .upright(let book):
            face(book, length: flatLength(book, spineHeight), vertical: true)

        case .leaning(let book):
            let length = flatLength(book, spineHeight) * 0.97
            face(book, length: length, vertical: true)
                .rotationEffect(.degrees(ShelfView.leanDegrees), anchor: .bottomLeading)
                // Rotation doesn't change layout size, so reserve the tilted
                // book's real footprint by hand.
                .frame(width: item.footprint(spineHeight: spineHeight),
                       height: length, alignment: .bottomLeading)

        case .stack(let books):
            VStack(alignment: .leading, spacing: 0.5) {
                ForEach(books) { book in
                    face(book, length: flatLength(book, spineHeight), vertical: false)
                }
            }
        }
    }

    /// One book face. Upright: `length` runs vertically. Flat: it runs
    /// horizontally and the spine thickness becomes the bar's height.
    private func face(_ book: Book, length: CGFloat, vertical: Bool) -> some View {
        let cloth = book.cloth
        let base = spineBaseColor(cloth)
        let ink = spineInkColor(cloth)
        let thickness = book.spineWidth

        return ZStack {
            spineFill(base: base, cloth: cloth, vertical: vertical)

            gilt(ink, length: length, vertical: vertical)

            if thickness >= 12 {
                // Give the title more of the spine and let it scale harder
                // before truncation so narrow books still read clearly.
                let run = length * titleRunFraction
                Text(displayTitle(for: book))
                    .font(titleFont(for: book, thickness: thickness))
                    .kerning(titleKerning(for: book))
                    .foregroundStyle(ink.opacity(theme == .artsy ? 0.96 : 0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(minimumScaleFactor(for: book))
                    .allowsTightening(true)
                    .truncationMode(.middle)
                    .frame(width: run)
                    .rotationEffect(.degrees(vertical ? 90 : 0))
                    .frame(width: vertical ? thickness : length,
                           height: vertical ? run : thickness)
            }
        }
        .frame(width: vertical ? thickness : length,
               height: vertical ? length : thickness)
        .clipShape(RoundedRectangle(cornerRadius: 1.5, style: .continuous))
        .overlay(spineBorder)
        .shadow(color: spineShadowColor, radius: shadowRadius,
                x: vertical ? (theme == .artsy ? 0.8 : 1.5) : 0,
                y: vertical ? 0 : (theme == .artsy ? 0.7 : 1))
    }

    /// The pair of gilt rules near each end of a spine.
    private func gilt(_ ink: Color, length: CGFloat, vertical: Bool) -> some View {
        let bar = ink.opacity(theme == .realistic ? 0.32 : 0.38)
        let inset = length * 0.10
        return Group {
            if vertical {
                VStack(spacing: 2) {
                    Spacer().frame(height: inset)
                    bar.frame(height: 0.7)
                    bar.frame(height: 0.7)
                    Spacer()
                    bar.frame(height: 0.7)
                    Spacer().frame(height: inset)
                }
                .padding(.horizontal, 2.5)
            } else {
                HStack(spacing: 2) {
                    Spacer().frame(width: inset)
                    bar.frame(width: 0.7)
                    bar.frame(width: 0.7)
                    Spacer()
                    bar.frame(width: 0.7)
                    Spacer().frame(width: inset)
                }
                .padding(.vertical, 2.5)
            }
        }
    }

    private func titleFont(for book: Book, thickness: CGFloat) -> Font {
        switch theme {
        case .classic, .walnut, .realistic:
            switch book.typographyStyle {
            case .classic:
                .system(size: min(9.4, thickness * 0.43), weight: .medium, design: .serif)
            case .modern:
                .system(size: min(8.7, thickness * 0.40), weight: .semibold, design: .rounded)
            case .literary:
                .system(size: min(9, thickness * 0.41), weight: .regular, design: .serif)
            case .scholarly:
                .system(size: min(8.2, thickness * 0.37), weight: .medium, design: .monospaced)
            }
        case .artsy:
            .system(size: min(9.5, thickness * 0.44), weight: .regular, design: .rounded)
        }
    }

    private func displayTitle(for book: Book) -> String {
        switch book.typographyStyle {
        case .modern:
            book.spineTitle
        case .classic, .literary, .scholarly:
            book.spineTitle.uppercased()
        }
    }

    private func titleKerning(for book: Book) -> CGFloat {
        if theme == .artsy { return 0.15 }

        switch book.typographyStyle {
        case .classic:
            return 0.32
        case .modern:
            return 0.05
        case .literary:
            return 0.22
        case .scholarly:
            return 0
        }
    }

    private func minimumScaleFactor(for book: Book) -> CGFloat {
        switch book.typographyStyle {
        case .scholarly:
            return 0.42
        case .modern:
            return 0.48
        case .classic, .literary:
            return 0.38
        }
    }

    private var titleRunFraction: CGFloat {
        switch theme {
        case .artsy:
            0.90
        case .classic, .walnut, .realistic:
            0.93
        }
    }

    private func spineBaseColor(_ cloth: Cloth) -> Color {
        switch theme {
        case .classic:
            Color(red: cloth.r, green: cloth.g, blue: cloth.b)
        case .walnut:
            Color(red: cloth.r * 0.88, green: cloth.g * 0.88, blue: cloth.b * 0.86)
        case .realistic:
            Color(red: min(1, cloth.r * 0.93 + 0.08),
                  green: min(1, cloth.g * 0.93 + 0.08),
                  blue: min(1, cloth.b * 0.93 + 0.08))
        case .artsy:
            Color(
                red: min(1, cloth.r * 0.86 + 0.12),
                green: min(1, cloth.g * 0.86 + 0.12),
                blue: min(1, cloth.b * 0.86 + 0.12)
            )
        }
    }

    private func spineInkColor(_ cloth: Cloth) -> Color {
        switch theme {
        case .classic:
            cloth.isLight
                ? Color(red: 0.18, green: 0.13, blue: 0.09)
                : Color(red: 0.93, green: 0.89, blue: 0.78)
        case .walnut:
            cloth.isLight
                ? Color(red: 0.16, green: 0.10, blue: 0.06)
                : Color(red: 0.90, green: 0.84, blue: 0.68)
        case .realistic:
            cloth.isLight
                ? Color(red: 0.25, green: 0.23, blue: 0.20)
                : Color(red: 0.98, green: 0.97, blue: 0.92)
        case .artsy:
            cloth.isLight
                ? Color(red: 0.23, green: 0.20, blue: 0.18)
                : Color.white.opacity(0.96)
        }
    }

    @ViewBuilder
    private func spineFill(base: Color, cloth: Cloth, vertical: Bool) -> some View {
        switch theme {
        case .classic:
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(LinearGradient(
                    colors: [base.opacity(0.82), base, base, shade(cloth, -0.28)],
                    startPoint: vertical ? .leading : .top,
                    endPoint: vertical ? .trailing : .bottom))
        case .walnut:
            realisticSpineTexture(index: bookTextureName, vertical: vertical)
                .colorMultiply(base)
                .overlay(
                    LinearGradient(
                        colors: [.white.opacity(0.08), .clear, .black.opacity(0.22)],
                        startPoint: vertical ? .leading : .top,
                        endPoint: vertical ? .trailing : .bottom
                    )
                )
                .overlay(
                    Rectangle()
                        .fill(.white.opacity(0.04))
                        .blur(radius: 0.3)
                        .offset(x: vertical ? 0.5 : 0, y: vertical ? 0 : 0.5)
                )
        case .realistic:
            realisticSpineTexture(index: bookTextureName, vertical: vertical)
                .colorMultiply(base)
                .overlay(
                    LinearGradient(
                        colors: [.white.opacity(0.14), .clear, .black.opacity(0.12)],
                        startPoint: vertical ? .leading : .top,
                        endPoint: vertical ? .trailing : .bottom
                    )
                )
                .overlay(
                    Rectangle()
                        .fill(.white.opacity(0.06))
                        .blur(radius: 0.3)
                        .offset(x: vertical ? 0.5 : 0, y: vertical ? 0 : 0.5)
                )
        case .artsy:
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [base.opacity(0.95), base.opacity(0.78)],
                        startPoint: vertical ? .leading : .top,
                        endPoint: vertical ? .trailing : .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .stroke(.white.opacity(0.16), lineWidth: 0.8)
                        .blur(radius: 0.4)
                )
                .overlay(
                    StripeOverlay(vertical: vertical)
                        .opacity(0.22)
                        .blendMode(.multiply)
                )
        }
    }

    private var spineBorder: some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .strokeBorder(spineBorderColor, lineWidth: theme == .artsy ? 0.85 : 0.5)
    }

    private var bookTextureName: String {
        String(format: "spine-%02d", item.books.first?.textureIndex ?? 1)
    }

    private var spineBorderColor: Color {
        switch theme {
        case .classic:
            .black.opacity(0.30)
        case .walnut:
            .black.opacity(0.32)
        case .realistic:
            Color(red: 0.35, green: 0.34, blue: 0.31).opacity(0.24)
        case .artsy:
            Color(red: 0.20, green: 0.18, blue: 0.17).opacity(0.55)
        }
    }

    private var spineShadowColor: Color {
        switch theme {
        case .classic:
            .black.opacity(0.45)
        case .walnut:
            .black.opacity(0.42)
        case .realistic:
            .black.opacity(0.16)
        case .artsy:
            Color(red: 0.45, green: 0.41, blue: 0.36).opacity(0.28)
        }
    }

    private var shadowRadius: CGFloat {
        switch theme {
        case .realistic:
            1.4
        case .walnut:
            1.8
        case .classic, .artsy:
            1.5
        }
    }

    @ViewBuilder
    private func realisticSpineTexture(index: String, vertical: Bool) -> some View {
        if let image = ThemeAssetImage.named(index) {
            image
                .resizable()
                .rotationEffect(.degrees(vertical ? 0 : 90))
                .aspectRatio(contentMode: .fill)
        } else {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color.white.opacity(0.20), .white.opacity(0.10), .black.opacity(0.16)],
                    startPoint: vertical ? .leading : .top,
                    endPoint: vertical ? .trailing : .bottom))
        }
    }
}

private struct Board: View {
    let thickness: CGFloat
    let theme: ShelfTheme

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: theme == .artsy ? 2 : 0, style: .continuous)
                .fill(boardGradient)
                .overlay(boardOverlay)
                .frame(height: thickness)
            Rectangle()
                .fill(boardLipColor)
                .frame(height: 1)
        }
        .shadow(color: boardShadowColor,
                radius: theme == .realistic ? 2.4 : 2.5, y: theme == .realistic ? 1.5 : 2)
    }

    private var boardGradient: LinearGradient {
        switch theme {
        case .classic:
            LinearGradient(colors: [Color(red: 0.42, green: 0.29, blue: 0.18),
                                    Color(red: 0.30, green: 0.20, blue: 0.12)],
                           startPoint: .top, endPoint: .bottom)
        case .walnut:
            LinearGradient(colors: [Color(red: 0.39, green: 0.24, blue: 0.13),
                                    Color(red: 0.19, green: 0.10, blue: 0.05)],
                           startPoint: .top, endPoint: .bottom)
        case .realistic:
            LinearGradient(colors: [Color(red: 0.96, green: 0.93, blue: 0.84),
                                    Color(red: 0.78, green: 0.74, blue: 0.64)],
                           startPoint: .top, endPoint: .bottom)
        case .artsy:
            LinearGradient(colors: [Color(red: 0.76, green: 0.69, blue: 0.54),
                                    Color(red: 0.67, green: 0.60, blue: 0.47)],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    @ViewBuilder
    private var boardOverlay: some View {
        switch theme {
        case .classic:
            EmptyView()
        case .walnut:
            EmptyView()
        case .realistic:
            Rectangle()
                .fill(.white.opacity(0.12))
                .frame(maxHeight: .infinity, alignment: .top)
        case .artsy:
            StripeOverlay(vertical: false)
                .opacity(0.24)
                .blendMode(.multiply)
        }
    }

    private var boardLipColor: Color {
        switch theme {
        case .realistic:
            Color(red: 0.45, green: 0.44, blue: 0.41).opacity(0.32)
        case .artsy:
            .black.opacity(0.18)
        case .classic, .walnut:
            .black.opacity(0.35)
        }
    }

    private var boardShadowColor: Color {
        switch theme {
        case .realistic:
            .black.opacity(0.18)
        case .classic, .walnut, .artsy:
            .black.opacity(0.35)
        }
    }
}

private struct Backdrop: View {
    let theme: ShelfTheme

    var body: some View {
        ZStack {
            switch theme {
            case .classic:
                LinearGradient(colors: [Color(red: 0.16, green: 0.12, blue: 0.09),
                                        Color(red: 0.09, green: 0.07, blue: 0.05)],
                               startPoint: .top, endPoint: .bottom)
            case .walnut:
                RadialGradient(colors: [Color(red: 0.20, green: 0.14, blue: 0.09),
                                        Color(red: 0.06, green: 0.045, blue: 0.03)],
                               center: .center, startRadius: 20, endRadius: 220)
            case .realistic:
                LinearGradient(colors: [Color(red: 0.42, green: 0.39, blue: 0.29),
                                        Color(red: 0.25, green: 0.23, blue: 0.17)],
                               startPoint: .top, endPoint: .bottom)
            case .artsy:
                LinearGradient(colors: [Color(red: 0.97, green: 0.95, blue: 0.90),
                                        Color(red: 0.92, green: 0.89, blue: 0.82)],
                               startPoint: .top, endPoint: .bottom)
            }

            if theme == .artsy {
                StripeOverlay(vertical: false)
                    .opacity(0.07)
                    .blendMode(.multiply)
            }

            if let assetName, let image = ThemeAssetImage.named(assetName, subdirectory: "ThemeAssets/Shelves") {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
    }

    private var assetName: String? {
        switch theme {
        case .walnut:
            "dark-oak"
        case .realistic:
            "white-built-in"
        case .classic, .artsy:
            nil
        }
    }
}

private struct ShelfPlate: View {
    let theme: ShelfTheme

    var body: some View {
        Group {
            switch theme {
            case .walnut:
                if let image = ThemeAssetImage.named("shelf-row") {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .overlay(
                            LinearGradient(colors: [.black.opacity(0.06), .clear, .black.opacity(0.16)],
                                           startPoint: .top, endPoint: .bottom)
                        )
                } else {
                    EmptyView()
                }
            case .realistic:
                ZStack {
                    Rectangle()
                        .fill(
                            LinearGradient(colors: [Color(red: 0.43, green: 0.40, blue: 0.30),
                                                    Color(red: 0.24, green: 0.22, blue: 0.16)],
                                           startPoint: .top, endPoint: .bottom)
                        )
                    Rectangle()
                        .fill(.black.opacity(0.06))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                    Rectangle()
                        .stroke(.white.opacity(0.04), lineWidth: 1)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                }
            case .classic, .artsy:
                EmptyView()
            }
        }
        .clipped()
    }
}

private struct ShelfSide: View {
    let theme: ShelfTheme
    let lightOnLeadingSide: Bool

    var body: some View {
        LinearGradient(
            colors: colors,
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var colors: [Color] {
        switch theme {
        case .realistic:
            return lightOnLeadingSide
                ? [Color.white.opacity(0.75), Color(red: 0.76, green: 0.71, blue: 0.61)]
                : [Color(red: 0.76, green: 0.71, blue: 0.61), Color.black.opacity(0.14)]
        case .walnut:
            return lightOnLeadingSide
                ? [Color(red: 0.45, green: 0.28, blue: 0.15), Color(red: 0.18, green: 0.09, blue: 0.04)]
                : [Color(red: 0.18, green: 0.09, blue: 0.04), Color.black.opacity(0.42)]
        case .classic, .artsy:
            return [.clear, .clear]
        }
    }
}

private struct ShelfFrame: View {
    let theme: ShelfTheme

    var body: some View {
        if theme == .walnut || theme == .realistic {
            RoundedRectangle(cornerRadius: theme == .realistic ? 24 : 16, style: .continuous)
                .strokeBorder(frameGradient, lineWidth: theme == .realistic ? 12 : 11)
                .overlay {
                    RoundedRectangle(cornerRadius: theme == .realistic ? 20 : 13, style: .continuous)
                        .strokeBorder(.black.opacity(theme == .realistic ? 0.18 : 0.44), lineWidth: 1.2)
                        .padding(theme == .realistic ? 8 : 7)
                }
                .shadow(color: .black.opacity(theme == .realistic ? 0.20 : 0.42), radius: 5, y: 3)
                .allowsHitTesting(false)
        }
    }

    private var frameGradient: LinearGradient {
        if theme == .realistic {
            return LinearGradient(
                colors: [Color(red: 0.99, green: 0.97, blue: 0.91),
                         Color(red: 0.80, green: 0.75, blue: 0.65)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [Color(red: 0.49, green: 0.30, blue: 0.15),
                     Color(red: 0.20, green: 0.10, blue: 0.045)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private func shade(_ c: Cloth, _ f: Double) -> Color {
    Color(red: max(0, c.r + f), green: max(0, c.g + f), blue: max(0, c.b + f))
}

private struct StripeOverlay: View {
    let vertical: Bool

    var body: some View {
        GeometryReader { geo in
            Path { path in
                let span = vertical ? geo.size.width : geo.size.height
                let length = vertical ? geo.size.height : geo.size.width
                var offset: CGFloat = 0
                while offset <= span + 4 {
                    if vertical {
                        path.move(to: CGPoint(x: offset, y: 0))
                        path.addLine(to: CGPoint(x: offset, y: length))
                    } else {
                        path.move(to: CGPoint(x: 0, y: offset))
                        path.addLine(to: CGPoint(x: length, y: offset))
                    }
                    offset += 4
                }
            }
            .stroke(.black.opacity(0.35), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }
}

private enum ThemeAssetImage {
    private static let subdirectory = "ThemeAssets/Realistic/final"

    static func named(_ name: String, subdirectory: String = subdirectory) -> Image? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: subdirectory) else {
            return nil
        }

        #if canImport(UIKit)
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        return Image(uiImage: image)
        #elseif canImport(AppKit)
        guard let image = NSImage(contentsOf: url) else { return nil }
        return Image(nsImage: image)
        #else
        return nil
        #endif
    }
}
