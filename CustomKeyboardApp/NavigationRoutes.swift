import Foundation

/// Typed navigation values.
///
/// `NavigationStack` destinations are keyed by type, so every level of the
/// editor gets its own small value type instead of passing raw UUIDs around.
struct LayoutRoute: Hashable {
    var id: UUID
}

struct RowRoute: Hashable {
    var layoutID: UUID
    var rowID: UUID
}

struct KeyRoute: Hashable {
    var layoutID: UUID
    var keyID: UUID
}

struct ThemeRoute: Hashable {
    var id: UUID
}

struct PresetRoute: Hashable {
    var index: Int
}

struct AboutRoute: Hashable {
    var unused: Int = 0
}
