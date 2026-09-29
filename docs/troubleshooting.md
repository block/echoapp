---
title: Troubleshooting
description: Diagnose discovery, connection, plugin loading, and data-flow problems.
section: Start here
permalink: /troubleshooting/
---

# Troubleshooting

Start at the connection boundary, then move inward: can the Mac see the device, can EchoApp connect,
and does the client advertise the plugin you expect?

## A device does not appear

### iOS or macOS client

- Confirm the client called `EchoClient.start()` in the running development build.
- Put the Mac and physical device on the same local network.
- In **System Settings → Privacy & Security → Local Network**, allow EchoApp to access the network.
- Allow local-network access for the client app when iOS asks.
- Relaunch the client after changing network permissions.
- As a fallback for simulator discovery issues, use the Swift client's manual connection mode with
  the WebSocket URL shown by EchoApp.

### Android client

- Run `adb devices` and confirm the target is listed and authorized.
- Start the Android `EchoClient` in the active debug process.
- If you use a physical device, confirm USB debugging is enabled and accept its authorization prompt.
- Restart the ADB server with `adb kill-server && adb start-server` if its device list is stale.

## EchoApp connects but a plugin is missing

- The client and desktop plugins must use exactly the same identifier.
- Register the client plugin before calling `start()`.
- Confirm the plugin is included in the active build variant, not only declared as a dependency.
- Rebuild both sides after changing a payload contract or plugin identifier.
- For a third-party desktop plugin, check that its `.echoplugin` bundle is in
  `~/Library/Application Support/Echo/Plugins/` and supports the installed EchoApp version.

## A plugin is visible but has no data

- Trigger the behavior after the connection is established; many plugins do not replay old events.
- Keep a strong reference to your client plugin for as long as EchoClient is running.
- Check encoding errors where the client calls `PluginConnection.send`.
- Verify that the desktop side decodes the same field names, types, and date representation.
- Use the CLI's `plugins list` and `tail` commands to distinguish transport problems from UI problems.

```sh
echoapp plugins list
echoapp tail --follow
```

## EchoApp crashes while loading plugins

Move third-party bundles out of the plugin directory and relaunch:

```sh
mkdir -p "$TMPDIR/echo-disabled-plugins"
mv "$HOME/Library/Application Support/Echo/Plugins/"*.echoplugin \
  "$TMPDIR/echo-disabled-plugins/"
```

Restore the bundles one at a time to identify the incompatible plugin. Built-in plugins are part of
the app and are unaffected by this directory.

## Still stuck?

Search the [issue tracker](https://github.com/block/echoapp/issues). If the problem is new, open an
issue with the EchoApp version, OS version, client platform, minimal reproduction steps, and
sanitized logs. Never attach raw captures that contain credentials or user data.
