# Package Products, Traits, and Availability

Choose the smallest product and trait set that satisfies the consumer. Traits are opt-in and have no defaults.

## Library products

| Product | Contract |
| --- | --- |
| `Lexicon` | Document, parser, graph, validation, composition, search primitives, branches, and CRDT model. |
| `SwiftLexicon` | Runtime values, keyed event details, observers, streams, and generated Swift support. |
| `LexiconGenerators` | Generator protocols, registry, and built-in language generators. |
| `LexiconSearchMLX` | MLX-backed embedding provider when the `MLXSearch` trait is enabled. |
| `_JSON` | Implementation and generated-runtime JSON support; no independent compatibility promise. |
| `_Collections` | Implementation collection support; no independent compatibility promise. |

## Executables and plugins

| Product | Contract |
| --- | --- |
| `lexicon` | Structured validation, lint, inspection, search, formatting, diff, excerpt, and editing commands. |
| `lexicon-generate` | Source and interchange-format generation. |
| `lexicon-lsp` | Sidecar language server for reference completion and diagnostics. |
| `SwiftLibraryGeneratorPlugin` | SwiftPM build-tool plugin producing Swift that depends on `SwiftLexicon`. |
| `SwiftStandAloneGeneratorPlugin` | SwiftPM build-tool plugin producing stand-alone Swift. |

## Traits

| Trait | Default | Effect |
| --- | --- | --- |
| `Editor` | Disabled | Exposes incremental graph-editing APIs in `Lexicon`; read-only clients do not compile editor-only surface. |
| `MLXSearch` | Disabled | Links MLX/tokenizer dependencies and enables the MLX embedding provider used by semantic CLI search. |

Run trait-specific validation when adopting either surface:

```sh
swift test --traits Editor
swift build --traits MLXSearch --product lexicon
```

MLX availability is narrower than the core package's portability. Keep deterministic token and lexical search as the fallback for unsupported consumers.

## Platform evidence

Package declarations and CI evidence answer different questions:

| Platform | Package declaration | Current evidence |
| --- | --- | --- |
| macOS 15+ | Declared | Built and tested in CI. |
| iOS 18+ | Declared | No dedicated iOS compile or runtime-test CI job. |
| Linux | SwiftPM host platform | Built and tested in CI using deterministic platform fallbacks. |
| Android | Not a declared Apple deployment platform | Experimental and not currently verified by emulator or ARM64 cross-build CI. |

Only promote a platform claim after a named, required job provides the stated compile or test evidence. Natural-language graph facilities may use Apple's NaturalLanguage where available; deterministic fallbacks keep core APIs usable elsewhere.
