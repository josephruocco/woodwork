import AppIntents

enum WidgetShelf: Int, AppEnum {
    case one = 1
    case two
    case three
    case four
    case five
    case six

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Shelf"
    static let caseDisplayRepresentations: [WidgetShelf: DisplayRepresentation] = [
        .one: "Shelf 1 · 3 rows",
        .two: "Shelf 2 · 3 rows",
        .three: "Shelf 3 · 3 rows",
        .four: "Shelf 4 · 2 rows",
        .five: "Shelf 5 · 2 rows",
        .six: "Shelf 6 · 2 rows"
    ]
}

struct SelectShelfIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "WoodWork Shelf"
    static let description = IntentDescription("Choose a different Shelf number for different books and layouts.")

    @Parameter(title: "Shelf", default: .one)
    var shelf: WidgetShelf
}
