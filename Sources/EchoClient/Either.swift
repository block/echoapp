public enum Either<T, U> {
    case left(T)
    case right(U)

    public var left: T? {
        if case let .left(value) = self { return value }
        return nil
    }

    public var right: U? {
        if case let .right(value) = self { return value }
        return nil
    }
}

// MARK: -

extension Either: Equatable where T: Equatable, U: Equatable {

    public static func == (lhs: Either<T, U>, rhs: Either<T, U>) -> Bool {
        switch (lhs, rhs) {
        case let (.left(lhs), .left(rhs)) where lhs == rhs: return true
        case let (.right(lhs), .right(rhs)) where lhs == rhs: return true
        default: return false
        }
    }
}

extension Either: Sendable where T: Sendable, U: Sendable {}
