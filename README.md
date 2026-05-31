# Lexicon

_Recurrent vocabularies, ontologies and naming systems for software that is meant to keep growing._

Lexicon is a Swift package, document format, CLI, language server and code-generation toolkit for turning domain language into a living semantic graph.

It is for teams whose shared language is scattered across API paths, UI copy, analytics events, feature flags, JSON keys, diagrams, tickets and tribal memory. A lexicon gives that language somewhere to live: somewhere it can be read, edited, versioned, composed, validated, traversed and compiled into platform code.

## Documentation

The README is the short overview. The detailed guides now live in the wiki:

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

`lexicon-lsp` provides completions and diagnostics for Lexicon document references, Go exact-path calls and Rust exact-path macros.

```sh
swift build -c release --product lexicon-lsp
```

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

See [CLI Reference](https://github.com/ollieatkinson/Lexicon/wiki/CLI-Reference) and [Search](https://github.com/ollieatkinson/Lexicon/wiki/Search).

## Package Products

| Product | Purpose |
| --- | --- |
| `Lexicon` | Core document, graph, parser, composition, branch and CRDT model. |
| `SwiftLexicon` | Runtime support for generated Swift lexicons and event streams. |
| `LexiconGenerators` | Code generators and generator registry. |
| `_JSON` | JSON value and decoder-backed typed access. |
| `_Collections` | Internal collection utilities, including sorted dictionary support. |
| `lexicon` | CLI for validating, inspecting, formatting, diffing and editing lexicons. |
| `lexicon-generate` | CLI for generating source artefacts. |
| `lexicon-lsp` | Sidecar language server for Lexicon path completions and diagnostics. |
| `SwiftLibraryGeneratorPlugin` | SwiftPM plugin for generated Swift that depends on `SwiftLexicon`. |
| `SwiftStandAloneGeneratorPlugin` | SwiftPM plugin for stand-alone generated Swift. |

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
```

The package currently declares Swift 6.3, Swift language mode 6, macOS 15 and iOS 18.

## Platform Support

CI runs SwiftPM tests on macOS and Linux. It also runs tests on an Android emulator and cross-builds Android ARM64.

On Apple platforms, sentence graph generation can use NaturalLanguage. On Linux and Android, Lexicon uses a deterministic fallback so the API remains available.

See [Platform Support](https://github.com/ollieatkinson/Lexicon/wiki/Platform-Support).

## Development

```sh
swift test -Xswiftc -warnings-as-errors
swift test -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
```

## Status

Lexicon is usable as a Swift package and command-line toolkit. The active branch is `trunk`; pin a commit if you need grammar or source compatibility.

The formal document specification is still evolving. Near-term work is focused on clearer examples, richer search and discovery APIs, and more editor-oriented composition workflows.
