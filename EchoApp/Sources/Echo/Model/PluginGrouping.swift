import EchoPluginAPI
import Foundation
import IdentifiedCollections

public typealias SectionID = String

public struct SectionRef: Identifiable, Equatable {
    public let id: SectionID
    let plugins: IdentifiedArrayOf<LoadedPlugin>
}

/// The key in DesktopPluginMetadata this section is grouped by.
public enum MetadataGroupKey: String, Equatable, CaseIterable {
    case category = "Category"
    case targetAppDisplayName = "Target App"
}

extension UserDefaults {
    private enum Keys {
        static let disabledPlugins = "echo.app.disabledPluginIdentifiers"
        static let collapsedSections = "echo.app.collapsedSectionsList"
        static let sectionGroupingKey = "MainSidebar.sectionGroupingKey"
    }

    var sectionGroupingKey: MetadataGroupKey {
        guard let key = string(forKey: Keys.sectionGroupingKey),
              let metadataGroupKey = MetadataGroupKey(rawValue: key)
        else {
            return .targetAppDisplayName
        }
        return metadataGroupKey
    }

    var disabledPluginIdentifiers: [String]? {
        get { array(forKey: Keys.disabledPlugins) as? [String] }
        set { set(newValue, forKey: Keys.disabledPlugins) }
    }

    var collapsedSections: [String]? {
        get { array(forKey: Keys.collapsedSections) as? [String] }
        set { set(newValue, forKey: Keys.collapsedSections) }
    }
}
