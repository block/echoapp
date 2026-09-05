import Foundation

// MARK: -

extension Error {

    var detailedDescription: String {
        if let localizedError = self as? LocalizedError {
            return localizedError.detailedDescription
        }
        return localizedDescription
    }
}

// MARK: -

extension LocalizedError {

    var detailedDescription: String {
        var components: [String] = []

        if let errorDescription {
            components.append("Error: \(errorDescription)")
        }
        if let failureReason {
            components.append("Reason: \(failureReason)")
        }
        if let recoverySuggestion {
            components.append("Suggestion: \(recoverySuggestion)")
        }
        if let helpAnchor {
            components.append("Help Anchor: \(helpAnchor)")
        }

        return components.isEmpty ? "No error details available." : components.joined(separator: "\n")
    }
}
