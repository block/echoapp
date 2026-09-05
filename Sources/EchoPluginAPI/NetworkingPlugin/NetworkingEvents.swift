import Foundation

public typealias HumanReadableResponse = Response<String>
public typealias RawResponse = Response<Data?>

/// The Echo networking plugin supports two modes: **Proxy** and **Passive**.
///
/// **Proxy Mode**
/// Echo executes network requests _on behalf of the client_,
/// giving users full control over request behavior. Through EchoApp.app’s UI, users can:
/// delay requests, use predefined fixtures, proxy requests to a different server,
/// or simulate HTTP errors.
///
/// **Passive Mode**
/// The client executes network requests normally (e.g., via `URLSession`).
/// EchoApp.app passively records requests and responses, providing users with a reviewable history.
///
/// **Proxy Mode**
///```
/// +---------+       +----------+       +---------+
/// | Client  |       |  Echo    |       |   Web   |
/// +---------+       |  Server  |       +---------+
///      |            +----------+           |
///      |                 |                 |
///      | request(proxy=true)               |
///      |---------------->|                 |
///      |                 |                 |
///      |                 |  HTTP Request   |
///      |                 |---------------> |
///      |                 |                 |
///      |                 |  HTTP Response  |
///      |                 |<--------------- |
///      |                 |                 |
///      | NetworkingPluginServerEvent       |
///      |<----------------|                 |
///      |                 |                 |
///      | finalizedResponse                 |
///      |---------------->|                 |
/// ```
///
///
/// **Passive Mode**
/// ```
/// +---------+       +---------+        +---------+
/// | Client  |       |  Echo   |        |   Web   |
/// +---------+       |  Server |        +---------+
///      |            +---------+             |
///      |                 |                  |
///      | request(proxy=false)               |
///      |---------------->|                  |
///      |                 |                  |
///      |  HTTP Request   |                  |
///      |----------------------------------->|
///      |                 |                  |
///      |  HTTP Response  |                  |
///      |<-----------------------------------|
///      |                 |                  |
///      | finalizedResponse                  |
///      |---------------->|                  |
/// ```

/// Events sent by the client
public enum NetworkingPluginClientEvent: Codable {

    /// The client made a request.
    ///
    /// - If `proxy` is `true`, Echo will **execute the request on behalf of** the client:
    ///     1. The client **pauses execution** until Echo sends a response (`NetworkingPluginServerEvent`).
    ///     2. The client processes the response and sends `.finalizedResponse` to complete the interaction.
    ///
    /// - If `proxy` is `false`:
    ///     1. The client **executes the request independently** using `URLSession` (or another networking API).
    ///     2. The client **still sends** `.request(proxy: false)` to **notify Echo** that a request is being made.
    ///     3. The client receives and processes the HTTP response **directly from the Web server**.
    ///     4. The client sends `.finalizedResponse` to Echo to signal that the request is complete.
    ///
    /// In both cases, the client must **always** send `.finalizedResponse` when done.
    case request(Request, proxy: Bool)

    /// The client should **always** send this when completing a network request,
    /// regardless of whether or not the request was proxied.
    /// This response should be human readable (i.e. binary messages should be converted to JSON or another human-readable format).
    case finalizedResponse(HumanReadableResponse)

    /// The client encountered an error. See `Error` enum for possible reasons.
    case error(Error, requestID: String)

    /// Well-known errors emitted by the client plugin
    public enum Error: Codable, Equatable {

        /// EchoApp.app sent a human-readable response (i.e. a fixture) to the client, but the client
        /// failed to convert it to the expected format (e.g. a protobuf).
        /// EchoApp.app will display the error and allow the user to provide a different response.
        case failedToParseProposedHumanReadableResponse(reason: String)
    }
}

/// Events sent by the server (EchoApp.app) when using **Proxy Mode**
public enum NetworkingPluginServerEvent: Codable {

    /// EchoApp.app provided a raw HTTP response (typically by proxying the original request).
    /// The client should use the provided response, then send `.finalizedResponse` to complete the interaction.
    case rawResponse(RawResponse)

    /// EchoApp.app provided a human-readable response (typically a fixture).
    /// The client should parse the response and use it, then send `.finalizedResponse` to complete the interaction.
    case proposedHumanReadableResponse(HumanReadableResponse)
}
