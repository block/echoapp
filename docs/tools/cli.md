---
title: Command-line interface
description: Connect to a device, capture every plugin stream as JSONL, and query it without the GUI.
section: Tools
permalink: /tools/cli/
---

# Command-line interface

The `echoapp` executable is a headless EchoApp host. It discovers iOS and Android clients, writes
plugin events to structured JSONL files, and exposes commands for querying sessions and controlling
supported debug tools.

## Build the CLI

From a source checkout:

```sh
cd EchoApp
swift build --product echoapp
.build/debug/echoapp --help
```

Release archives may also include the executable. Keep the CLI and client SDK on compatible release
versions when possible.

## Connect

List available clients, then connect by name or identifier:

```sh
echoapp connect --list
echoapp connect "iPhone 17 Pro"
```

`connect` is long-running. Leave it in a terminal, `tmux`, or `screen` session while another shell
queries the capture. Set `ECHO_DATA_DIR` when a script needs a stable output location:

```sh
ECHO_DATA_DIR=/tmp/echo-data echoapp connect "Pixel_9_API_36"
```

## Inspect a session

```sh
echoapp status
echoapp sessions
echoapp plugins list
echoapp tail networking --follow
```

The current session contains `session.json` plus one JSONL file per plugin that has sent data. Each
line records a timestamp, plugin identifier, and the plugin's data. Omit the plugin name to merge
all plugin streams in timestamp order, for example `echoapp tail --follow`.

## Query captured data

```sh
echoapp query networking --url "/api/v1/profile" --last 5m
echoapp query networking --method POST --status 500
echoapp query analytics --event "screen_view"
echoapp query logging --level error --format compact
```

Use `--session <id>` to query an older session and `--limit <count>` to cap output. The default JSONL
format is easy to pipe into `jq` or another program.

## Discover plugin-specific commands

```sh
echoapp plugins list --format agent
echoapp plugins info networking
```

Installed plugins can ship agent-oriented documentation next to their metadata. The `agent` format
summarizes available streams and useful query filters without hard-coding every plugin into the CLI.

## Work with debug controls

When the connected app exposes the Debug Menu plugin, the CLI can inspect and mutate its controls:

```sh
echoapp debugmenu list
echoapp debugmenu find "staging"
echoapp debugmenu set-toggle use-staging --on
echoapp debugmenu select api-environment 1
```

Run `echoapp debugmenu --help` before automating a mutation. Identifiers and available operations belong
to the connected app, not to EchoApp itself.

## Automate safely

- Record a baseline before triggering an action, then process only appended JSONL lines.
- Do not truncate active session files; create a new session or use `echoapp clear`.
- Treat captures as sensitive and delete temporary data when the task is complete.
- Use deterministic plugin and item identifiers instead of display names in scripts.
