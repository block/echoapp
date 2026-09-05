import Foundation
import os

extension Logger {

    public static func echoLogger(category: String) -> Logger {
        .init(subsystem: "xyz.block.echoapp", category: category)
    }
}

