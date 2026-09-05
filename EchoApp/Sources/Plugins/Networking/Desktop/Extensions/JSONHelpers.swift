import Foundation

// MARK: -

extension Dictionary {

    var prettyPrintedJSON: String {
        do {
            let data = try JSONSerialization.data(
                withJSONObject: self,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            )
            return String(data: data, encoding: .utf8) ?? description
        } catch {
            return description
        }
    }

}

// MARK: -

extension Encodable {

    var prettyPrintedJSON: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(self) {
            return String(decoding: data, as: UTF8.self)
        }
        return ""
    }

}

// MARK: -

extension Decodable {

    static func parse(fromJSON json: String) throws -> Self {
        let decoder = JSONDecoder()
        return try decoder.decode(self, from: Data(json.utf8))
    }

}
