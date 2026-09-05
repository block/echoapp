# Echo Desktop Plugin UI

## Overview

A library of standard UI elements for Desktop Plugin development. `EchoTableView` serves 90% of the use cases, but it's up to you if you want to use it. 

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Installation](#installation)
- [Usage](#usage)
    - [Initialization](#initialization)
    - [Configuration](#configuration)
    - [Custom Inspector Footer](#custom-inspector-footer)
    - [Connecting to a Plugin](#connecting-to-a-plugin)

## Features

- SwiftUI-based UI for macOS.
- EchoTableRow data management and display.
- Detailed Inspector View for Rows.
- Search Capabilities.
- UI for play/pause/clear the data.

## Requirements

- macOS 14+
- Swift 5.10+

## Installation

`EchoPluginUI` ships as part of the `EchoDesktopPlugin` product of this package. Add the dependency to your project using Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/block/echoapp", from: "0.1.0")
]
```

Then, add the library to your target:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "EchoDesktopPlugin", package: "echoapp")
    ]
)
```

## Usage

### Initialization

To create your own desktop plugin, create a class that conforms to `DesktopPlugin` 

```swift
import SwiftUI
import Combine
import EchoPluginAPI
import EchoPluginUI

final class HelloWorldDesktopPlugin: DesktopPlugin {

    // MARK: - Plugin

    let metadata = DesktopPluginMetadata(
        id: "com.company.helloworld",
        version: "0.0.1",
        category: .observability,
        displayName: "Hello World",
        icon: Image(systemName: "hand.wave"),
        description: ""
    )

    private let viewModel = EchoTableViewModel()

    func makeView() -> AnyView {
        AnyView(
           EchoTableView(
                viewModel: viewModel,
                inspectorFooter: { _ in
                    EmptyView()
                }
            )
        )
    }

    func onConnect(_ connection: PluginConnection) {
        viewModel.connect(connection: connection)
    }

    func onDisconnect() {
        viewModel.disconnect()
    }

}
```

### Configuration

Use `EchoTableViewModel.Configuration` to customize the UI

```swift
let configuration = EchoTableViewModel.Configuration(
    customColumnConfiguration: [
        EchoColumnKey(id: "Time", width: 110), 
        EchoColumnKey(id: "Name", width: 110), 
        EchoColumnKey(id: "Language", width: 200)
        EchoColumnKey(id: "Greeting")
    ],
    maxRowCount: 2000,
    detailViewTitleKey: "Greeting"
)

let viewModel = EchoTableViewModel(configuration: configuration)
```

### Custom Inspector Footer

Add a custom footer to the Inspector to handle things like actions 
```swift
let pluginUI =EchoTableView(viewModel: viewModel) { row in
    CustomFooterView(row: row)
}
```

### Connecting to a Plugin

Parsing and displaying data from the connection is handled for you using these convenience methods:

```swift
viewModel.connect(connection: connection)
viewModel.disconnect()
```

You can add a separate .sink on the connection to handle other data types that aren't an `EchoTableRow`.
