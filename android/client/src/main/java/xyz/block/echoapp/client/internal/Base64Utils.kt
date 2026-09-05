package xyz.block.echoapp.client.internal

import okio.ByteString.Companion.decodeBase64
import okio.ByteString.Companion.encodeUtf8

internal fun String.encodeToBase64String(): String = encodeUtf8().base64()

internal fun String.decodeBase64ToString(): String = decodeBase64()?.utf8().orEmpty()
