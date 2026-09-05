package xyz.block.echoapp.client

/**
 * Represents the current state of an [EchoClient]. May be observed via [EchoClient.clientState].
 */
sealed interface ClientState {
  /** The client has an active connection from the desktop app. */
  data object Connected : ClientState

  /**
   * The client does not have an active connection from the desktop app, and the client is not
   * discoverable to the desktop app.
   */
  data object Disconnected : ClientState

  /** The client does not have an active connection, but is discoverable to the desktop app. */
  data object Advertising : ClientState
}
