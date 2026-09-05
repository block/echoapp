package xyz.block.echoapp.sample

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.util.fastForEachIndexed
import androidx.core.content.edit
import xyz.block.echoapp.client.EchoClient
import xyz.block.echoapp.client.UnixDomainSocketServer
import xyz.block.echoapp.client.transport.TunnelSocketFactory
import xyz.block.echoapp.plugin.accessibility.AccessibilityPlugin
import xyz.block.echoapp.plugin.keyvaluestore.KeyValueStorePlugin
import xyz.block.echoapp.plugin.keyvaluestore.providers.SharedPrefsKeyValueStoresProvider
import xyz.block.echoapp.plugin.logging.EchoTree
import xyz.block.echoapp.plugin.logging.LoggingPlugin
import xyz.block.echoapp.sample.keyvaluestore.FakeImmutableKeyValueStoresProvider
import xyz.block.echoapp.sample.ui.theme.EchoTheme
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.LazyThreadSafetyMode.SYNCHRONIZED
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import okhttp3.OkHttpClient
import timber.log.Timber

class MainActivity : ComponentActivity() {
  private val timeFormatter = SimpleDateFormat("HH:mm:ss.SSS", Locale.getDefault())

  private val udsConnectionHandshaker = UnixDomainSocketServer()

  // Single OkHttp client configured for tunneling over the Unix domain socket
  private val tunnelOkHttpClient: OkHttpClient by
      lazy(SYNCHRONIZED) {
        OkHttpClient.Builder().socketFactory(TunnelSocketFactory(udsConnectionHandshaker)).build()
      }

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    setContent {
      val loggingPlugin = remember {
        LoggingPlugin(
            currentTimestampProvider = { timeFormatter.format(Date(System.currentTimeMillis())) },
        )
      }

      val accessibilityPlugin = remember { AccessibilityPlugin() }

      val keyValueStorePlugin = remember {
        getSharedPreferences("sample_prefs", MODE_PRIVATE).edit {
          putBoolean("sample_boolean_key", true)
          putInt("sample_int_key", 1234)
          putString("sample_string_key", "Hello, world!")
        }
        KeyValueStorePlugin(
            storesProviders =
                listOf(
                    FakeImmutableKeyValueStoresProvider(),
                    SharedPrefsKeyValueStoresProvider(this),
                ),
        )
      }

      // Reuse the instance installed in SampleApplication so onConnect can flush persisted crashes.
      val crashReportingPlugin = remember {
        (application as SampleApplication).crashReportingPlugin
      }

      val udsEchoClient = remember {
        EchoClient.Builder(
                context = this,
                connectionHandshaker = udsConnectionHandshaker,
                okHttpClient = tunnelOkHttpClient,
            )
            .addPlugins(
                loggingPlugin,
                accessibilityPlugin,
                keyValueStorePlugin,
                crashReportingPlugin,
            )
            .build()
      }

      val echoClient = remember {
        EchoClient.Builder(context = this)
            .addPlugins(
                loggingPlugin,
                accessibilityPlugin,
                keyValueStorePlugin,
                crashReportingPlugin,
            )
            .build()
      }

      val echoTree = remember { EchoTree(loggingPlugin) }

      DisposableEffect(Unit) {
        Timber.plant(echoTree)

        onDispose { Timber.uproot(echoTree) }
      }

      EchoTheme {
        // A surface container using the 'background' color from the theme
        Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
          EchoHome(
              echoClient = echoClient,
              udsEchoClient = udsEchoClient,
          )
        }
      }
    }
  }
}

@Composable
private fun EchoHome(
    modifier: Modifier = Modifier,
    echoClient: EchoClient?,
    udsEchoClient: EchoClient?,
) {
  val scope = rememberCoroutineScope()
  val radioOptions = listOf("NSD Advertiser", "Unix Domain Socket Server")
  var selectedOptionIndex by remember { mutableIntStateOf(0) }

  // Create EchoClient based on selected option
  val currentEchoClient =
      remember(selectedOptionIndex) {
        if (selectedOptionIndex == 0) {
          echoClient
        } else {
          udsEchoClient
        }
      }

  Column(
      modifier = modifier.fillMaxSize(),
      verticalArrangement = Arrangement.Center,
      horizontalAlignment = Alignment.CenterHorizontally,
  ) {
    Text(
        text = "Use Echo with",
        style = MaterialTheme.typography.headlineMedium,
        modifier = Modifier.padding(bottom = 16.dp),
    )

    Column(modifier = Modifier.selectableGroup()) {
      radioOptions.fastForEachIndexed { index, text ->
        Row(
            Modifier.fillMaxWidth()
                .height(56.dp)
                .selectable(
                    selected = index == selectedOptionIndex,
                    onClick = { selectedOptionIndex = index },
                    role = Role.RadioButton,
                )
                .padding(horizontal = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
          RadioButton(
              selected = index == selectedOptionIndex,
              onClick = null,
          )
          Text(
              text = text,
              style = MaterialTheme.typography.bodyLarge,
              modifier = Modifier.padding(start = 16.dp),
          )
        }
      }
    }

    Spacer(modifier = Modifier.height(32.dp))

    Button(onClick = { scope.launch(Dispatchers.IO) { currentEchoClient?.start() } }) {
      Text(text = "Start Echo")
    }
    Button(onClick = { scope.launch(Dispatchers.IO) { currentEchoClient?.stop() } }) {
      Text(text = "Stop Echo")
    }

    Spacer(modifier = Modifier.height(32.dp))

    // Forcibly crash the app to exercise CrashReportingPlugin. The crash is persisted to disk by
    // the uncaught exception handler and sent to desktop after relaunching and tapping Start Echo.
    Button(
        onClick = {
          throw RuntimeException(
              "Forced crash from Echo sample app",
              IllegalStateException("Simulated root cause"),
          )
        }
    ) {
      Text(text = "Force Crash")
    }
  }
}

@Preview(
    showSystemUi = true,
    showBackground = true,
)
@Composable
private fun EchoHomePreview() {
  EchoTheme { EchoHome(echoClient = null, udsEchoClient = null) }
}
