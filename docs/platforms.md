# Platform Support

Lexicon is verified on macOS and Linux with `swift test`. CI also runs the SwiftPM tests on an Android emulator.

On Apple platforms, `Lexicon.Graph.from(sentences:)` uses NaturalLanguage for tokenization and lexical classes. On platforms without NaturalLanguage, Lexicon uses a small deterministic tokenizer and lexical-class fallback so sentence graphs remain available for Linux and Android builds.

Android support is verified in two ways: cross-compiling the package with the official Swift SDK for Android, and running the SwiftPM tests on an Android API 28 emulator. The Android build job installs the Swift 6.3.2 Android SDK, configures Android NDK r27d, and builds both Android API 28 SDK triples:

```sh
swift build --swift-sdk aarch64-unknown-linux-android28 --static-swift-stdlib
swift build --swift-sdk x86_64-unknown-linux-android28 --static-swift-stdlib
```

The Android test job uses the emulator harness from `skiptools/swift-android-action` because SwiftPM cross-compilation alone builds the test runner but does not execute it on an Android runtime.
