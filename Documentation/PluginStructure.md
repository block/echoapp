# Plugin Structure

Echo uses a custom macOS bundle structure, it mostly follows the [Loadable Bundles](https://developer.apple.com/library/archive/documentation/CoreFoundation/Conceptual/CFBundles/BundleTypes/BundleTypes.html#//apple_ref/doc/uid/10000123i-CH101-SW30) structure from Apple.

Echo plugin bundles end with: `.echoplugin` and a basic bundle which contains `.framework` file which is to be loaded by `EchoApp.app` may look like:

```sh
MyPlugin.echoplugin
└── Contents
    ├── Info.plist
    ├── MacOS
    │   └── MyPlugin.framework
    └── _CodeSignature
```

The `Info.plist` for the `.echoplugin` should contain at least the following:

```plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleIdentifier</key>
	<string>com.example.MyPlugin</string>
	<key>CFBundleName</key>
	<string>MyPlugin</string>
	<key>CFBundlePackageType</key>
	<string>BNDL</string>
	<key>CFBundleSupportedPlatforms</key>
	<array>
		<string>MacOSX</string>
	</array>
</dict>
</plist>

```
