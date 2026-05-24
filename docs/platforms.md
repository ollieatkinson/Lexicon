# Platform Support

Lexicon is verified on macOS and Linux with `swift test`.

Android support is verified by cross-compiling the package with the official Swift SDK for Android. The CI job installs the Swift 6.3.2 Android SDK, configures Android NDK r27d, and builds both Android API 28 SDK triples:

```sh
swift build --swift-sdk aarch64-unknown-linux-android28 --static-swift-stdlib
swift build --swift-sdk x86_64-unknown-linux-android28 --static-swift-stdlib
```

Android CI is build-only. Running tests on Android requires a device or emulator harness, so Linux remains the non-Darwin runtime test target for now.
