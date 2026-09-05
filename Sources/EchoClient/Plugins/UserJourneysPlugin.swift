
import Combine
import EchoPluginAPI
import Foundation

public final class UserJourneysPlugin: ClientPlugin {

    public struct Event: Identifiable, Codable {

        public enum EventType: Equatable, Codable {
            case start
            case tag
            case variant
            case frustrationSignal
            case frictionSignal
            case end(outcome: String)
            case log
            case updateActiveJourney(activeJourneysData: String?)
            case report(requestData: String)

            enum CodingKeys: String, CodingKey {
                case type
                case outcome
                case activeJourneysData
                case requestData
            }

            // MARK: - Decoding

            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                let type = try container.decode(String.self, forKey: .type)

                switch type {
                case "start":
                    self = .start
                case "tag":
                    self = .tag
                case "variant":
                    self = .variant
                case "frustrationSignal":
                    self = .frustrationSignal
                case "frictionSignal":
                    self = .frictionSignal
                case "end":
                    let outcome = try container.decode(String.self, forKey: .outcome)
                    self = .end(outcome: outcome)
                case "log":
                    self = .log
                case "updateActiveJourney":
                    let data = try container.decodeIfPresent(String.self, forKey: .activeJourneysData)
                    self = .updateActiveJourney(activeJourneysData: data)
                case "report":
                    let data = try container.decode(String.self, forKey: .requestData)
                    self = .report(requestData: data)
                default:
                    throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Invalid event type")
                }
            }

            // MARK: - Encoding

            public func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)

                switch self {
                case .start:
                    try container.encode("start", forKey: .type)
                case .tag:
                    try container.encode("tag", forKey: .type)
                case .variant:
                    try container.encode("variant", forKey: .type)
                case .frustrationSignal:
                    try container.encode("frustrationSignal", forKey: .type)
                case .frictionSignal:
                    try container.encode("frictionSignal", forKey: .type)
                case let .end(outcome):
                    try container.encode("end", forKey: .type)
                    try container.encode(outcome, forKey: .outcome)
                case .log:
                    try container.encode("log", forKey: .type)
                case let .updateActiveJourney(data):
                    try container.encode("updateActiveJourney", forKey: .type)
                    try container.encodeIfPresent(data, forKey: .activeJourneysData)
                case let .report(data):
                    try container.encode("report", forKey: .type)
                    try container.encode(data, forKey: .requestData)
                }
            }
        }

        // MARK: - Public Properties

        public let id: UUID
        public let timestamp: Date
        public let journeyName: String
        public let eventType: EventType
        public let eventValue: String
        public let metadata: [String: String]?

        // MARK: - Life Cycle

        public init(
            id: UUID = UUID(),
            timestamp: Date = Date(),
            journeyName: String = "",
            eventType: EventType,
            eventValue: String,
            metadata: [String: String]? = nil
        ) {
            self.id = id
            self.timestamp = timestamp
            self.journeyName = journeyName
            self.eventType = eventType
            self.eventValue = eventValue
            self.metadata = metadata
        }

        enum CodingKeys: String, CodingKey {
            case id
            case timestamp
            case journeyName
            case eventValue
            case eventType
            case metadata
        }
    }

    public enum DesktopPluginEvent {
        case active
        case inactive
    }

    public let id: PluginIdentifier = "com.block.plugin.userjourneys"
    public let version = "1.0"

    private var connection: PluginConnection?

    private let desktopPluginEventSubject = PassthroughSubject<DesktopPluginEvent, Never>()

    /// A publisher that emits events when the desktop plugin becomes active or inactive.
    /// Subscribers can use this to react to changes in the plugin's state.
    public var desktopPluginEventPublisher: AnyPublisher<DesktopPluginEvent, Never> {
        desktopPluginEventSubject.eraseToAnyPublisher()
    }

    public init() {}

    // MARK: - ClientPlugin

    public func onConnect(_ connection: PluginConnection) {
        self.connection = connection
    }

    public func onDisconnect() {
        self.connection = nil
    }

    public func onDesktopPluginActive() {
        desktopPluginEventSubject.send(.active)
    }
    public func onDesktopPluginInactive() {
        desktopPluginEventSubject.send(.inactive)
    }

}

extension UserJourneysPlugin {

    /// Sends a journey event to the connection.
    /// - Parameter event: The event to send.
    private func sendJourneyEvent(event: UserJourneysPlugin.Event) {
        do {
            try self.connection?.send(event)
        } catch {
            print("UserJourneysEchoPlugin Failed to encode JourneyEvent: \(error)")
        }
    }

    /// Notifies that a journey has started.
    /// - Parameters:
    ///   - userJourneyName: The name of the journey that started.
    ///   - timeout: The timeout duration for the journey, in seconds.
    ///   - metadata: Additional metadata for the event.
    public func didStartJourney(
        userJourneyName: String,
        timeout: TimeInterval,
        metadata: [String: String]? = nil
    ) {
        var eventMetadata = metadata ?? [:]
        eventMetadata["timeout"] = "\(timeout)"

        sendJourneyEvent(
            event: .init(
                journeyName: userJourneyName,
                eventType: .start,
                eventValue: userJourneyName,
                metadata: eventMetadata
            )
        )
    }

    /// Adds a variant to the journey.
    /// - Parameters:
    ///   - userJourneyName: The name of the journey.
    ///   - variant: The variant to add.
    ///   - metadata: Additional metadata for the event.
    public func didAddVariant(
        userJourneyName: String,
        variant: String,
        metadata: [String: String]? = nil
    ) {
        sendJourneyEvent(
            event: .init(
                journeyName: userJourneyName,
                eventType: .variant,
                eventValue: variant,
                metadata: metadata
            )
        )
    }

    /// Adds a frustration signal to the journey.
    /// - Parameters:
    ///   - userJourneyName: The name of the journey.
    ///   - frustrationSignal: The frustration signal to add.
    ///   - metadata: Additional metadata for the event.
    public func didAddFrustrationSignal(
        userJourneyName: String,
        frustrationSignal: String,
        metadata: [String: String]? = nil
    ) {
        sendJourneyEvent(
            event: .init(
                journeyName: userJourneyName,
                eventType: .frustrationSignal,
                eventValue: frustrationSignal,
                metadata: metadata
            )
        )
    }

    /// Adds a friction signal to the journey.
    /// - Parameters:
    ///   - userJourneyName: The name of the journey.
    ///   - frictionSignal: The friction signal to add.
    ///   - metadata: Additional metadata for the event.
    public func didAddFrictionSignal(
        userJourneyName: String,
        frictionSignal: String,
        metadata: [String: String]? = nil
    ) {
        sendJourneyEvent(
            event: .init(
                journeyName: userJourneyName,
                eventType: .frictionSignal,
                eventValue: frictionSignal,
                metadata: metadata
            )
        )
    }

    /// Adds a tag to the journey.
    /// - Parameters:
    ///   - userJourneyName: The name of the journey.
    ///   - tag: The tag to add.
    ///   - metadata: Additional metadata for the event.
    public func didAddTag(
        userJourneyName: String,
        tag: String,
        metadata: [String: String]? = nil
    ) {
        sendJourneyEvent(
            event: .init(
                journeyName: userJourneyName,
                eventType: .tag,
                eventValue: tag,
                metadata: metadata
            )
        )
    }

    /// Notifies that a journey has ended.
    /// - Parameters:
    ///   - userJourneyName: The name of the journey that ended.
    ///   - outcome: The outcome of the journey.
    ///   - metadata: Additional metadata for the event.
    public func didEndJourney(
        userJourneyName: String,
        outcome: String,
        metadata: [String: String]? = nil
    ) {
        sendJourneyEvent(
            event: .init(
                journeyName: userJourneyName,
                eventType: .end(outcome: outcome),
                eventValue: userJourneyName,
                metadata: metadata
            )
        )
    }

    /// Updates active journeys UI.
    /// - Parameters:
    ///   - jsonRepresentation: The JSON representation of all the active journeys.
    ///   - currentActiveJourneyName: The name of the current active journey at the top of the stack in the event of multiple journeys.
    ///   Set `nil` to indicate that there is no active journey.
    ///   - metadata: Additional metadata for the event.
    public func didUpdateActiveJourneys(
        activeJourneysJSONRepresentation: String,
        currentActiveJourneyName: String?,
        metadata: [String: String]? = nil
    ) {
        sendJourneyEvent(
            event: .init(
                journeyName: currentActiveJourneyName ?? "",
                eventType: .updateActiveJourney(activeJourneysData: activeJourneysJSONRepresentation),
                eventValue: currentActiveJourneyName ?? "",
                metadata: metadata
            )
        )
    }

    /// Reports a user journey.
    /// - Parameters:
    ///   - userJourneyName: The name of the journey to report.
    ///   - metadata: Additional metadata for the event.
    public func didReportUserJourney(
        userJourneyName: String,
        requestJSONRepresentation: String,
        metadata: [String: String]? = nil
    ) {
        sendJourneyEvent(
            event: .init(
                journeyName: userJourneyName,
                eventType: .report(requestData: requestJSONRepresentation),
                eventValue: "",
                metadata: metadata
            )
        )
    }

    /// Adds logs to the journey timeline for debugging and code navigation purposes.
    /// These can be analytics events or any log that's useful for implementing journeys.
    /// The logs will automatically be placed in the context of the currentActiveJourney set by `didUpdateActiveJourneys()`.
    /// - Parameters:
    ///   - message: The message to log.
    ///   - metadata: Additional metadata for the event.
    public func log(
        message: String,
        metadata: [String: String]? = nil
    ) {
        sendJourneyEvent(
            event: .init(
                journeyName: "",
                eventType: .log,
                eventValue: message,
                metadata: metadata
            )
        )
    }
}
