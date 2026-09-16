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
        .one: "Shelf 1",
        .two: "Shelf 2",
        .three: "Shelf 3",
        .four: "Shelf 4",
        .five: "Shelf 5",
        .six: "Shelf 6"
    ]
}

struct SelectShelfIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "WoodWork Shelf"
    static let description = IntentDescription("Choose a different Shelf number for different books and layouts.")

    @Parameter(title: "Shelf", default: .one)
    var shelf: WidgetShelf
}
