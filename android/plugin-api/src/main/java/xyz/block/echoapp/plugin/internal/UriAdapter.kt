package xyz.block.echoapp.plugin.internal

import android.net.Uri
import androidx.core.net.toUri
import com.squareup.moshi.FromJson
import com.squareup.moshi.ToJson

/** Moshi adapter for Uri <-> string. */
@Suppress("unused")
internal class UriAdapter {
  @FromJson fun fromJson(string: String?): Uri? = string?.toUri()

  @ToJson fun toJson(uri: Uri?): String? = uri?.toString()
}
