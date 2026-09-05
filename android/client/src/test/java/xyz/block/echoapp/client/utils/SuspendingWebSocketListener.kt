package xyz.block.echoapp.client.utils

import app.cash.turbine.Turbine
import kotlinx.coroutines.CompletableDeferred
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString
import okio.ByteString.Companion.encodeUtf8

open class SuspendingWebSocketListener : WebSocketListener() {
  private val messages = Turbine<ByteString>()
  private val socket = CompletableDeferred<WebSocket>()

  override fun onOpen(
      webSocket: WebSocket,
      response: Response,
  ) {
    super.onOpen(webSocket, response)
    socket.complete(webSocket)
  }

  override fun onMessage(
      webSocket: WebSocket,
      bytes: ByteString,
  ) {
    super.onMessage(webSocket, bytes)
    messages.add(bytes)
  }

  override fun onMessage(
      webSocket: WebSocket,
      text: String,
  ) {
    super.onMessage(webSocket, text)
    messages.add(text.encodeUtf8())
  }

  suspend fun awaitMessage(): ByteString = messages.awaitItem()

  suspend fun awaitSocketOpened(): WebSocket = socket.await()
}
