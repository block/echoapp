import Foundation

struct OperationTimeoutError: LocalizedError, Equatable, Sendable {
    let seconds: TimeInterval

    var errorDescription: String? {
        "Operation timed out after \(seconds.formatted()) seconds."
    }
}

extension Sequence {
    
    func asyncCompactMap<T>(
        _ transform: (Element) async throws -> T?
    ) async rethrows -> [T] {
        var values = [T]()

        for element in self {
            if let transformed = try await transform(element) {
                values.append(transformed)
            }
        }

        return values
    }
}

func withTimeout<T>(
    seconds: TimeInterval,
    operation: @escaping () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw OperationTimeoutError(seconds: seconds)
        }
        
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
