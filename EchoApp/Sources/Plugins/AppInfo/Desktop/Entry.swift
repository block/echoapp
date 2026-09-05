struct Entry: Codable, Identifiable {
    var scope: String
    var key: String
    var value: String

    var id: String { key }
}
