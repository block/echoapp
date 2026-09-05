package xyz.block.echoapp.plugin.synchub

import com.squareup.moshi.Json

enum class SyncOperationType {
  @Json(name = "initialize_domain") INITIALIZE_DOMAIN,
  @Json(name = "sync_domain") SYNC_DOMAIN,
  @Json(name = "write_domain") WRITE_DOMAIN,
  @Json(name = "read_domain") READ_DOMAIN,
}

enum class SyncOperationStatus {
  @Json(name = "success") SUCCESS,
  @Json(name = "error") ERROR,
}
