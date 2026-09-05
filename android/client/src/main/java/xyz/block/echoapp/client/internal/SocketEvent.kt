package xyz.block.echoapp.client.internal

import okhttp3.WebSocket
import okio.ByteString

internal sealed class SocketEvent {
  data class OnOpen(val webSocket: WebSocket) : SocketEvent()

  data object OnClose : SocketEvent()

  data class OnMessage(
      val data: ByteString,
  ) : SocketEvent()
}
