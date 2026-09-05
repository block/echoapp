import Foundation

public extension String {

    var prettyPrintedJSONString: String {
        return Data(self.utf8).prettyPrintedJSONString ?? self
    }

    var camelCaseToCustomerFacingText: String {
        return self.replacingOccurrences(
            of: "([A-Z])",
            with: " $1",
            options: .regularExpression,
            range: self.range(of: self)
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .capitalized
    }
}
