# Lexicon

_Recurrent vocabularies, ontologies and naming systems for software that is meant to keep growing._

Lexicon is a Swift package, document format and code-generation toolkit for turning domain language into a living semantic graph.

It is for teams whose shared language is scattered across API paths, UI copy, analytics events, feature flags, JSON keys, diagrams, tickets and tribal memory. A lexicon gives that language somewhere to live: somewhere it can be read, edited, versioned, composed, validated, traversed and compiled into platform code.

Lexicon is intended as a foundation for ontology-led development, semantic reactive programming and [software gardening](https://github.com/thousandyears/garden). It is not one schema to rule every domain. It is an affordance for experts to express their own domains in their own terms, while still creating enough structure for those domains to communicate.

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

The gardening idea is that useful systems are not simply delivered from the top down. They are cultivated as environments with good affordances: each domain can grow independently, and each contribution can become a new surface for others to build on. Lexicon is one small piece of that: a language substrate for growing connected vocabularies without forcing every team into one monolingual taxonomy.

## A Lexicon Document

Lexicons are written in a compact TaskPaper-like format. Indentation is significant; use tabs.

This example keeps database, API, session, UI and UX terms separate, while still letting them refer to each other. It also uses document metadata, multiple roots and composition.

`commerce.lexicon`

```taskpaper
# Commerce language shared by API, UI, session and product surfaces.
> Product teams can add local dialects without replacing the shared vocabulary.
@ ./shared-commerce.lexicon

commerce:
# The main application vocabulary.
> Terms under this root are composed into generated platform code.
	db:
	@ ./data-types.lexicon
	session:
	# Runtime ownership is separate from API and UI ownership.
		configuration:
			value:
		state:
			value:
			shared:
				value:
				+ commerce.session.state.value
			stored:
				value:
				+ commerce.session.state.value
	api:
		storefront:
		@ ./storefront-api.lexicon
	ui:
		product:
		@ ./product-ui.lexicon
	ux:
		onboarding:
			choose:
				product:
				+ commerce.ux.type.story
					confirm:
					+ commerce.ux.type.task
support:
# A second root can still reference the commerce vocabulary.
	case:
	+ commerce.db.collection
		status:
		+ commerce.db.type.string
		? "open"
```

<details>
<summary><code>shared-commerce.lexicon</code></summary>

```taskpaper
commerce:
	db:
		collection:
			id:
			+ commerce.db.type.string
		leaf:
	session:
		configuration:
			value:
		state:
			value:
			shared:
				value:
				+ commerce.session.state.value
			stored:
				value:
				+ commerce.session.state.value
	ui:
		type:
		> Reusable controls are deliberately small; product screens compose them.
			control:
			label:
			card:
			+ commerce.ui.type.control
			button:
				primary:
				+ commerce.ui.type.control
				secondary:
				+ commerce.ui.type.control
	ux:
		type:
			action:
			story:
			task:
```

</details>

<details>
<summary><code>data-types.lexicon</code></summary>

```taskpaper
db:
	type:
		any:
		+ commerce.db.leaf
		boolean:
		+ commerce.db.leaf
		string:
		+ commerce.db.leaf
		tag:
		+ commerce.db.leaf
```

</details>

<details>
<summary><code>storefront-api.lexicon</code></summary>

```taskpaper
storefront:
	products:
	+ commerce.db.collection
		product:
		+ commerce.db.collection
			id:
			+ commerce.db.type.string
			title:
			+ commerce.db.type.string
			is:
				eligible:
				+ commerce.db.type.boolean
				+ commerce.session.state.value
			ineligible:
				reason:
				+ commerce.db.type.string
	order:
		create:
		+ commerce.ux.type.task
			can:
				submit:
				+ commerce.db.type.boolean
				+ commerce.session.configuration.value
			primary:
				action:
				+ commerce.ui.type.button.primary
				+ commerce.ux.type.action
```

</details>

<details>
<summary><code>product-ui.lexicon</code></summary>

```taskpaper
product:
	card:
	+ commerce.ui.type.card
		title:
		+ commerce.ui.type.label
		buy:
		+ commerce.ui.type.button.primary
		+ commerce.ux.type.action
		# UI says enabled; analytics may say active.
			enabled:
			+ commerce.api.storefront.order.create.can.submit
			? true
			active:
			= enabled
```

</details>

This is not just an outline. It says:

- `commerce.api.storefront.products.product` is a collection-backed API concept.
- `commerce.api.storefront.products.product.is.eligible` is both a boolean and a session value.
- `commerce.api.storefront.order.create.primary.action` is both a UI primary button and a UX action.
- `commerce.ui.product.card.buy.enabled` is typed by the API/session submit capability.
- `commerce.ui.product.card.buy.active` is a synonym for `enabled`, preserving a local UI dialect.
- `support.case.status` is a second root that still references the commerce vocabulary.
- `@ ./shared-commerce.lexicon`, `@ ./data-types.lexicon`, `@ ./storefront-api.lexicon` and `@ ./product-ui.lexicon` compose external vocabulary at different points in the document.
- `? true` and `? "open"` provide literal JSON defaults.
- `>` lines carry notes that can be surfaced as documentation metadata.
- `#` lines carry authoring comments that stay with the document for maintainers and tools.

The point is not that UI, API and session state should collapse into one model. The point is that they can stay separate and still share meaning.

## Syntax

| Syntax | Meaning |
| --- | --- |
| `name:` | Defines a lemma. Its full ID is its dot path, such as `commerce.ui.product.card`. |
| `+ commerce.db.type.string` | Adds a type reference. Types provide inherited children and default fallbacks. |
| `= enabled` | Makes a lemma a synonym of another lemma, resolved relative to the parent when possible. |
| `? true` | Sets a literal JSON default. Strings, numbers, booleans, arrays, objects and `null` are supported. |
| `? @ commerce.some.default` | Sets a default by reference. |
| `@ ./shared.lexicon` | Imports another lexicon. At document level it composes with the root; inside a node it grafts there. |
| `> note` | Adds a note to the current document or node. Notes are domain-facing prose and are included in generated JSON class metadata. |
| `# comment` | Adds a comment to the current document or node. Comments are authoring/tooling annotations and are preserved by the document, CLI and CRDT layers. |

Names must start with a letter and may contain letters, digits and underscores.

Notes and comments are separate because they usually have different audiences. A note explains the term to readers of the vocabulary. A comment explains the source document to maintainers, generators or editor tooling. Lexicon preserves both, but generators can choose which metadata is appropriate for their target.

## Mental Model

Lexicon has four core layers.

`Document` is parsed source. It can contain multiple roots, imports, notes, comments, nodes, type references, synonyms and defaults.

`Graph` is a selected root tree from a document. Documents may contain many roots; a graph has one root.

`Lexicon` is the resolved, actor-isolated object graph. It indexes lemmas by stable dot-path IDs and resolves inheritance, synonyms and defaults.

`Lemma` is a semantic node. A lemma knows its ID, parent, own children, inherited children, types, synonyms, default value and whether it comes from concrete source or inheritance.

Most application code should read through generated lexicons rather than stringly typed lookups. After generating Swift, the dot path becomes ordinary source:

```swift
import SwiftLexicon

let submit = commerce.api.storefront.order.create.can.submit
let enabled = commerce.ui.product.card.buy.enabled
let active = commerce.ui.product.card.buy.active

print(submit.__)
print(enabled == active)
```

## Composition

Lexicons can import other lexicons at document level or at a node.

```taskpaper
@ ./shared.lexicon

commerce:
	api:
		storefront:
		@ ./storefront.lexicon
	ui:
		product:
		@ ./product-ui.lexicon
```

Composition rebases imported roots and rewrites internal references so the imported branch keeps its meaning at the graft point.

```swift
let resolver = FileLexiconImportResolver(baseURL: source.deletingLastPathComponent())
let plan = try document.composed(resolving: resolver)

guard plan.conflicts.isEmpty else {
	throw ValidationError(plan.conflicts.map(\.description).joined(separator: "\n"))
}

let composed = plan.document
```

Branches can also be exported as self-contained lexicon fragments. External references are reported as diagnostics and imports are added where Lexicon can infer them.

## Code Generation

`lexicon-generate` turns a lexicon into source artefacts.

```sh
swift run lexicon-generate commerce.lexicon \
	--type swift,swift-standalone,kotlin,go,ts,json,json-ld
```

Available generator commands:

| Command | Output |
| --- | --- |
| `swift` | Swift source that imports `SwiftLexicon`. |
| `swift-standalone` | Stand-alone Swift source. |
| `kotlin` | Stand-alone Kotlin source. |
| `go` | Stand-alone Go source. |
| `ts` | Stand-alone TypeScript source. |
| `json` | JSON classes and mixins snapshot. |
| `json-ld` | SKOS JSON-LD. |

The generator registry lives in `LexiconGenerators`, and SwiftPM build-tool plugins are available for generated Swift sources.

## CLI

The `lexicon` executable is designed for scripts, editors and automation.

```sh
swift run lexicon validate commerce.lexicon
swift run lexicon lint commerce.lexicon
swift run lexicon inspect commerce.lexicon commerce.ui.product.card
swift run lexicon tree commerce.lexicon commerce --depth 4 --inherited --metadata
swift run lexicon search commerce.lexicon order submit --mode hybrid --limit 10
swift run lexicon refs commerce.lexicon commerce.ui.product.card.buy.enabled
swift run lexicon excerpt commerce.lexicon commerce.ui.product.card
swift run lexicon format commerce.lexicon --write
swift run lexicon diff before.lexicon after.lexicon
```

Search supports lexical phrase matching, token matching over IDs and metadata, and semantic ranking. The default `hybrid` mode is the normal entry point; use `--mode token`, `--mode lexical` or `--mode semantic` when you need a narrower lens. `--scope own` searches the declared graph, `--scope live` expands likely hits through resolved lemma context, and `--scope full` materializes the resolved search space with recursion detection. Use `--depth`, `--candidates`, and `--budget` to bound live and full traversal. On Apple platforms the base build can use NaturalLanguage sentence embeddings. To enable the MLX embedder backend, build the CLI with the `MLXSearch` package trait:

```sh
swift run --traits MLXSearch lexicon search commerce.lexicon "order submit" \
	--embedding-provider mlx \
	--embedding-model TaylorAI/bge-micro-v2
```

MLX document embeddings are cached under the user cache directory by default. The first semantic search builds the cache and logs indexing progress to stderr; pass `--embedding-cache` or `--rebuild-embeddings` to control that cache.

See [`docs/search.md`](docs/search.md) for the search mode guide and demo lexicon examples. See [`docs/search-platforms.md`](docs/search-platforms.md) for Linux, Android, Windows, and ONNX backend notes.

Editing commands print the updated document to stdout by default. Pass `-o` or `--output` to write another file.

```sh
swift run lexicon add commerce.lexicon commerce.ui.product.card badge \
	--type commerce.ui.type.label \
	--default '"New"' \
	-o commerce.next.lexicon

swift run lexicon rename commerce.lexicon commerce.ui.product.card.buy purchase \
	-o commerce.next.lexicon
```

Validation and inspection commands emit structured JSON so other tools can consume them.

## Runtime Events

`SwiftLexicon` is a small runtime for generated Swift lexicons and async event streams.

Generated Swift lexicons expose typed values for the graph. Events can be sent and matched by generated lemma, generated type or keyed value.

```swift
import SwiftLexicon

let events = Events()

let subscription = commerce.ux.type.action >> events.then { event in
	let value: String = try event[type: String.self]
	print(value)
}

commerce.ui.product.card.buy["birthday_001"] >> events

subscription.cancel()
events.finish()
```

Event payloads are JSON-backed and decode through `JSONDecoder`, so generated lexicons can carry structured values without hard-coded casts.

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

On Apple platforms, sentence graph generation uses NaturalLanguage. On Linux and Android, Lexicon uses a deterministic fallback so the API remains available.

See [`docs/platforms.md`](docs/platforms.md) for details.

## Development

```sh
swift test -Xswiftc -warnings-as-errors
swift test -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
```

## Status

Lexicon is usable as a Swift package and command-line toolkit. The active branch is `trunk`; pin a commit if you need grammar or source compatibility.

The formal document specification is still evolving. Near-term work is focused on clearer examples, richer search and discovery APIs, and more editor-oriented composition workflows.
