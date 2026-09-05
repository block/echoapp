import Foundation

extension URL {
    func parentPathComponent(where predicate: (_ pathComponent: String) -> Bool) -> URL? {
        if predicate(lastPathComponent) {
            return self
        }
        // Check if we've reached the root
        guard self.pathComponents.count > 1 else {
            return nil
        }
        return self.deletingLastPathComponent().parentPathComponent(where: predicate)
    }
}
