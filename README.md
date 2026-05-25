# Lexicon

_A specification for shared, indefinitely evolving namespaces, ontologies and languages that nurture diversity of dialects by enticing contributions from the native speakers of each domain of expertise in an organisation._

Lexicon is a Swift package for authoring, composing and generating code from domain vocabularies. It is intended as a foundation for ontology-led development, semantic reactive programming and [software gardening](https://github.com/thousandyears/garden).

While the project is still moving toward a formal 1.0 specification, [mindflare.app](https://mindflare.app) demonstrates the core ideas.

## What It Provides

- `Lexicon`: TaskPaper parsing, multi-root documents, document metadata, imports, branch export/paste, CRDT document merge, graph traversal and default-value resolution.
- `SwiftLexicon`: a Swift runtime for generated lexicons, using async event streams.
- `LexiconGenerators`: source generators for Swift, stand-alone Swift, Kotlin, Go, TypeScript, JSON class/mixin snapshots and SKOS JSON-LD.
- `_JSON`: a small JSON value package with decoder-backed typed access.
- `_Collections`: internal collection utilities, including `SortedDictionary`.
- `lexicon`: a script-friendly CLI for validating, inspecting, formatting, diffing and editing lexicon documents.
- `lexicon-generate`: a CLI for generating source artifacts from lexicon documents.

Platform notes live in [docs/platforms.md](docs/platforms.md). CI runs `swift test` on macOS and Linux, plus Android emulator tests and Android ARM64 cross-builds.

## Document Shape

Lexicons are authored in a TaskPaper-like format:

```taskpaper
# document comment
> document note
@ ./shared.lexicon
app:
	kind:
	item:
	+ app.kind
	? {"enabled":true}
	alias:
	= app.item
```

Documents may contain multiple roots. `@` imports can appear at document level or on a node to compose local lexicon branches. Nodes can carry notes, comments, type references, protonym/synonym references and literal or referenced default values.

## CLI

```sh
swift run lexicon validate path/to/app.lexicon
swift run lexicon inspect path/to/app.lexicon app.item
swift run lexicon tree path/to/app.lexicon app --inherited --metadata
swift run lexicon excerpt path/to/app.lexicon app.item
swift run lexicon format path/to/app.lexicon --write
```

Generate code with one or more generator commands:

```sh
swift run lexicon-generate path/to/app.lexicon --type swift,swift-standalone,kotlin,go,ts,json,json-ld
```

## Development

```sh
swift test -Xswiftc -warnings-as-errors
swift test -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
```

The package currently uses Swift 6.3 with macOS 15 and iOS 18 minimum platform declarations.

## Roadmap

- Formalize the Lexicon document and graph specification.
- Expand search and discovery APIs across inherited nodes, synonyms and inheritors.
- Fill out user-facing documentation and examples for composition, generation and runtime events.
