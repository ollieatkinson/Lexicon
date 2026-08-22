# Lexicon

_Recurrent vocabularies, ontologies and naming systems for software that is meant to keep growing._

Lexicon is a Swift package, document format, CLI, language server and code-generation toolkit for turning domain language into a living semantic graph.

It is for teams whose shared language is scattered across API paths, UI copy, analytics events, feature flags, JSON keys, diagrams, tickets and tribal memory. A lexicon gives that language somewhere to live: somewhere it can be read, edited, versioned, composed, validated, traversed and compiled into platform code.

## Documentation

The README is the short package overview. The GitHub wiki is the canonical home for narrative documentation: tutorials, workflows, examples, editor setup and troubleshooting.

- [Quick Start](https://github.com/ollieatkinson/Lexicon/wiki/Quick-Start)
- [Core Concepts](https://github.com/ollieatkinson/Lexicon/wiki/Core-Concepts)
- [Gardening Philosophy](https://github.com/ollieatkinson/Lexicon/wiki/Gardening-Philosophy)
- [Document Syntax](https://github.com/ollieatkinson/Lexicon/wiki/Document-Syntax)
- [Composition and Imports](https://github.com/ollieatkinson/Lexicon/wiki/Composition-and-Imports)
- [Commerce Example](https://github.com/ollieatkinson/Lexicon/wiki/Example-Commerce-Vocabulary)
- [CLI Reference](https://github.com/ollieatkinson/Lexicon/wiki/CLI-Reference)
- [Search](https://github.com/ollieatkinson/Lexicon/wiki/Search)
- [Code Generation](https://github.com/ollieatkinson/Lexicon/wiki/Code-Generation)
- [Editor Support](https://github.com/ollieatkinson/Lexicon/wiki/Editor-Support)

Language-specific generation guides:

- [Swift](https://github.com/ollieatkinson/Lexicon/wiki/Language-Swift)
- [Kotlin](https://github.com/ollieatkinson/Lexicon/wiki/Language-Kotlin)
- [Go](https://github.com/ollieatkinson/Lexicon/wiki/Language-Go)
- [Rust](https://github.com/ollieatkinson/Lexicon/wiki/Language-Rust)
- [TypeScript](https://github.com/ollieatkinson/Lexicon/wiki/Language-TypeScript)
- [JSON and SKOS JSON-LD](https://github.com/ollieatkinson/Lexicon/wiki/Language-JSON-and-SKOS-JSON-LD)

Editor setup guides:

- [Zed](https://github.com/ollieatkinson/Lexicon/wiki/Editor-Zed)
- [VS Code](https://github.com/ollieatkinson/Lexicon/wiki/Editor-VS-Code)
- [GoLand and JetBrains](https://github.com/ollieatkinson/Lexicon/wiki/Editor-GoLand-and-JetBrains)
- [Generic LSP Clients](https://github.com/ollieatkinson/Lexicon/wiki/Editor-Generic-LSP-Clients)

Versioned API guarantees and contributor policy stay with the source:

- [Lexicon 0.3 API contract](Documentation/Lexicon.docc/API-Contract-0.3.md)
- [Migrating from 0.2 to 0.3](Documentation/Lexicon.docc/Migration-0.3.md)
- [Package products and traits](Documentation/Lexicon.docc/Package-Traits.md)
- [Contributing](CONTRIBUTING.md)
- [Security policy](SECURITY.md)
- [Release process](RELEASING.md)

## Why

Most software systems do not have one language. Product, design, engineering, operations and data teams all name things from their own perspective.

That is healthy until the names become disconnected:

- API models drift away from UI states.
- Feature flags duplicate business concepts.
- Analytics events use names nobody can trace.
- Runtime state and persistent state grow separate vocabularies.
- Local domain language gets flattened into one implementation taxonomy.

Lexicon takes the opposite position:

- domain language should be a first-class artefact;
- dialects should be expected, not treated as noise;
- shared meaning should be composed, not imposed;
- experts should be able to express their own terms directly;
- source code can be generated from living language;
- the cost and risk of adding vocabulary should keep falling as the system grows.

Lexicon is intended as a foundation for ontology-led development, semantic reactive programming and [software gardening](https://github.com/thousandyears/garden). It is not one schema to rule every domain. It is an affordance for experts to express their own domains in their own terms, while still creating enough structure for those domains to communicate.

## A Small Lexicon

Lexicons are written in a compact TaskPaper-like format. Indentation is significant; use tabs.

```taskpaper
# Shared commerce vocabulary.
> API, UI, analytics and support can keep local words while sharing meaning.

commerce:
	type:
		boolean:
		string:
	api:
		order:
			submit:
			+ commerce.type.boolean
			? true
	ui:
		checkout:
			button:
				primary:
				+ commerce.api.order.submit
	analytics:
		event:
			checkout_started:
			+ commerce.ui.checkout.button.primary
	support:
		ticket:
			status:
			+ commerce.type.string
			? "open"
```

This defines stable paths such as `commerce.api.order.submit`, connects UI and analytics terms to the API concept, and gives `commerce.support.ticket.status` a default value.

See the [Commerce Example](https://github.com/ollieatkinson/Lexicon/wiki/Example-Commerce-Vocabulary) for a multi-file API, UI, session, UX and support vocabulary with imports, synonyms and generation examples.

## Code Generation

`lexicon-generate` turns a lexicon into source artefacts:

```sh
swift run lexicon-generate commerce.lexicon \
	--type swift,kotlin,go,rust,ts,json,json-ld
```

If the composed document contains more than one root, select the generated root
explicitly with `--root <name>`.

Available generator commands:

| Command | Output |
| --- | --- |
| `swift` | Swift source that imports `SwiftLexicon`. |
| `swift-standalone` | Stand-alone Swift source. |
| `kotlin` | Stand-alone Kotlin source. |
| `go` | Stand-alone Go source. |
| `rust` | Stand-alone Rust source. |
| `ts` | Stand-alone TypeScript source. |
| `json` | JSON classes and mixins snapshot. |
| `json-ld` | SKOS JSON-LD. |

Generated Swift turns dot paths into ordinary source:

```swift
import SwiftLexicon

let submit = commerce.api.order.submit
let button = commerce.ui.checkout.button.primary

print(submit.__)
print(button.__)
```

See [Code Generation](https://github.com/ollieatkinson/Lexicon/wiki/Code-Generation) and the language guides for target-specific setup.

## Editor Support

`lexicon-lsp` provides completions and diagnostics for Lexicon document references, quoted `l("...")` calls in any file-backed language and Rust exact-path macros.

```sh
swift build -c release --product lexicon-lsp
```

The VS Code extension lives in `Editors/VSCode/lexicon`. Once a workspace has Lexicon LSP configuration, it attaches the language server to file-backed documents so quoted `l("...")` completions can work outside a single language.

For most repositories, put one config file at the workspace root:

```json
{
  "lexicon": "commerce.lexicon"
}
```

Accepted config filenames are `lexicon-lsp.json`, `.lexicon-lsp.json`, `lexicon.conf` and `.lexicon.conf`.

See [Editor Support](https://github.com/ollieatkinson/Lexicon/wiki/Editor-Support), [Zed](https://github.com/ollieatkinson/Lexicon/wiki/Editor-Zed), [VS Code](https://github.com/ollieatkinson/Lexicon/wiki/Editor-VS-Code) and [GoLand and JetBrains](https://github.com/ollieatkinson/Lexicon/wiki/Editor-GoLand-and-JetBrains).

## CLI

The `lexicon` executable is designed for scripts, editors and automation.

```sh
swift run lexicon validate commerce.lexicon
swift run lexicon lint commerce.lexicon
swift run lexicon inspect commerce.lexicon commerce.ui.checkout.button.primary
swift run lexicon tree commerce.lexicon commerce --depth 4 --inherited --metadata
swift run lexicon search commerce.lexicon order submit --mode hybrid --limit 10
swift run lexicon refs commerce.lexicon commerce.ui.checkout.button.primary
swift run lexicon format commerce.lexicon --write
```

Search supports hybrid, semantic, token and lexical modes. The default `hybrid` mode is the normal entry point; use narrower modes when you need deterministic ID matching or semantic ranking.

```sh
swift run --traits MLXSearch lexicon search commerce.lexicon "order submit" \
	--embedding-provider mlx \
	--embedding-model TaylorAI/bge-micro-v2
```

MLX document embeddings are cached under the user cache directory by default. The first semantic search builds the cache and logs indexing progress to stderr; pass `--embedding-cache` or `--rebuild-embeddings` to control that cache.

For a portable ONNX Runtime backend, fetch the model/runtime artifacts with the SwiftPM command plugin, then build with the `ONNXSearch` trait:

```sh
swift package --disable-sandbox --allow-writing-to-package-directory \
	setup-onnx-search-artifacts -- \
	--preset bge-small-en-v1.5 \
	--runtime linux-x64

swift run --traits ONNXSearch lexicon search commerce.lexicon "order submit" \
	--mode semantic \
	--embedding-provider onnx \
	--embedding-model-preset bge-small-en-v1.5
```

ONNX presets currently include MiniLM, BGE-small, GTE-small and E5-small-v2. BGE-small is a good first ONNX model to try for semantic search, but `hybrid` remains the default because exact graph names and references still matter.

See [CLI Reference](https://github.com/ollieatkinson/Lexicon/wiki/CLI-Reference) and [Search](https://github.com/ollieatkinson/Lexicon/wiki/Search).

## Package Products

| Product | Purpose |
| --- | --- |
| `Lexicon` | Core document, graph, parser, composition, branch and CRDT model. |
| `SwiftLexicon` | Runtime support for generated Swift lexicons and event streams. |
| `LexiconGenerators` | Code generators and generator registry. |
| `LexiconSearchMLX` | MLX-backed embedding provider when the `MLXSearch` trait is enabled. |
| `LexiconSearchONNX` | ONNX Runtime embedding provider when the `ONNXSearch` trait is enabled. |
| `_JSON` | JSON support used by package and generated runtime code; no independent compatibility promise. |
| `_Collections` | Collection support used by package implementation; no independent compatibility promise. |
| `lexicon` | CLI for validating, inspecting, formatting, diffing and editing lexicons. |
| `lexicon-generate` | CLI for generating source artefacts. |
| `lexicon-lsp` | Sidecar language server for Lexicon path completions and diagnostics. |
| `SwiftLibraryGeneratorPlugin` | SwiftPM plugin for generated Swift that depends on `SwiftLexicon`. |
| `SwiftStandAloneGeneratorPlugin` | SwiftPM plugin for stand-alone generated Swift. |
| `ONNXSearchArtifactsPlugin` | SwiftPM command plugin for downloading ONNX search model and runtime artifacts. |

## Package Traits

Traits are opt-in and have no defaults:

| Trait | Effect |
| --- | --- |
| `Editor` | Enables incremental graph-editing APIs in `Lexicon`; read-only clients do not compile the editor-only surface. |
| `MLXSearch` | Links the MLX/tokenizer stack and enables MLX-backed semantic search in `LexiconSearchMLX` and `lexicon`. |
| `ONNXSearch` | Enables portable ONNX Runtime semantic search in `LexiconSearchONNX` and `lexicon`. |

Test or build the surface you adopt:

```sh
swift test --traits Editor
swift build --traits MLXSearch --product lexicon
swift build --traits ONNXSearch --product lexicon
```

See [Package products and traits](Documentation/Lexicon.docc/Package-Traits.md) for compatibility and availability boundaries.

## Installation

```swift
.package(
	url: "https://github.com/ollieatkinson/Lexicon.git",
	branch: "trunk"
)
```

Then depend on the products you need:

```swift
.product(name: "Lexicon", package: "Lexicon")
.product(name: "SwiftLexicon", package: "Lexicon")
.product(name: "LexiconGenerators", package: "Lexicon")
.product(name: "LexiconSearchMLX", package: "Lexicon")
.product(name: "LexiconSearchONNX", package: "Lexicon")
```

The package currently declares Swift 6.3, Swift language mode 6, macOS 15 and iOS 18.

## Platform Support

Package declarations and verification evidence are deliberately separate:

| Platform | Status | Evidence |
| --- | --- | --- |
| macOS 15+ | Supported | Built and tested in CI. |
| iOS 18+ | Declared | Package deployment target; no dedicated iOS CI job. |
| Linux | Supported | Built and tested in CI. |
| Android | Experimental | Not currently verified by emulator or ARM64 cross-build CI. |

On Apple platforms, sentence graph generation can use NaturalLanguage. Deterministic fallbacks keep the core API available when NaturalLanguage is unavailable. MLX-backed search has narrower host support and remains opt-in. ONNX-backed search is runtime-tested on Linux; its C shim is compile-tested on macOS, while Apple runtime setup and Android remain experimental.

See [Platform Support](https://github.com/ollieatkinson/Lexicon/wiki/Platform-Support).

## Development

```sh
swift test -Xswiftc -warnings-as-errors
swift test --traits Editor -Xswiftc -warnings-as-errors
swift test -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
python3 Scripts/verify_wiki_contract.py
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for the complete change and documentation workflow.

## Status

Lexicon is usable as a Swift package and command-line toolkit. The active branch is `trunk`; pin a commit if you need grammar or source compatibility.

The formal document specification is still evolving. The [0.3 API contract](Documentation/Lexicon.docc/API-Contract-0.3.md) and [migration guide](Documentation/Lexicon.docc/Migration-0.3.md) record the next compatibility boundary.
