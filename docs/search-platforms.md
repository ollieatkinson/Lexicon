# Search Platform Support

Lexicon search has two portability stories:

| Capability | macOS/iOS | Linux | Android | Windows direction |
| --- | --- | --- | --- | --- |
| `token` | Supported | Supported | Supported in library tests | Should be pure Swift |
| `lexical` | Supported | Supported | Supported in library tests | Should be pure Swift |
| `hybrid` without embeddings | Supported | Supported | Supported in library tests | Should be pure Swift |
| `semantic --embedding-provider system` | Uses `NaturalLanguage` | Not available | Not available | Not applicable |
| `semantic --embedding-provider mlx` | Supported with `MLXSearch` | Not promised | Not promised | Not applicable |
| Future `semantic --embedding-provider onnx` | Plausible | Preferred path | Preferred path | Preferred path |

`token`, `lexical`, and non-semantic `hybrid` search are implemented with Lexicon's own search entries, tokenizer, phrase scoring, and traversal logic. They do not require `NaturalLanguage`, MLX, ONNX, or a platform ML runtime.

Semantic search is different. The current lightweight system provider uses `NLEmbedding`, so it only exists where Apple's `NaturalLanguage` framework is present. The optional MLX provider is behind the `MLXSearch` package trait and works well on Apple platforms, but it should not be treated as the Linux or Android plan. `mlx-swift` has Linux work in its manifest, but the embedder stack used here (`mlx-swift-lm` and `swift-hf-api-mlx`) currently declares Apple platforms. That makes MLX a good Apple backend and a poor portability foundation.

## Current Gaps

| Gap | Impact | Needed work |
| --- | --- | --- |
| No portable semantic runtime | Linux and Android can run lexical/token search, but semantic results fall back to empty vectors unless MLX is built and usable. | Add a non-Apple embedding backend. |
| Tokenizer parity | Embedding models need the same tokenizer used at export/training time. | Pick one tokenizer strategy and include its identity in cache keys. |
| Native runtime packaging | Linux, Android, and Windows need different ONNX Runtime libraries and linker packaging. | Wrap ONNX Runtime C APIs behind a small Swift target plus per-platform binary/install notes. |
| Model lifecycle | A semantic backend needs model download, local cache, revision pinning, and offline mode. | Reuse the existing embedding cache shape, but extend the model descriptor. |
| CI coverage | PR CI proves pure Swift search on macOS/Linux. Android PR checks skip; semantic native runtimes are not exercised. | Add focused lexical/token Linux and Android tests now; add semantic jobs after an ONNX provider exists. |

## ONNX Direction

ONNX Runtime is the best next candidate for a portable semantic backend:

- Official compatibility docs list Windows, Linux, Mac, Android, and iOS as supported environments.
- The C API is available for C/C++ integration, which is the most realistic Swift interop path across Linux, Android, and Windows.
- Android distribution includes an `onnxruntime-android` AAR whose headers and `libonnxruntime.so` can be unpacked for NDK/C++ use.
- ONNX Runtime Mobile supports reduced/custom runtime builds for mobile deployment, which matters if we ship a small embedding model inside an app.

Useful references:

- <https://onnxruntime.ai/docs/reference/compatibility.html>
- <https://onnxruntime.ai/docs/get-started/with-c.html>
- <https://onnxruntime.ai/docs/install/>
- <https://onnxruntime.ai/docs/tutorials/mobile/>

The model choice should stay intentionally small at first. Good PoC candidates are ONNX exports of MiniLM, BGE-small, GTE-small, or similar sentence-embedding models. We need a model where the tokenizer files, pooling rule, output dimension, and normalization rule are explicit and reproducible.

## Provider Design

The public search design should not depend on SwiftPM traits. Traits are useful for packaging large optional dependencies, but they are the wrong abstraction boundary for search behavior.

Keep the core design like this:

```swift
public extension Lexicon.Search {
	protocol EmbeddingProvider: Sendable {
		var descriptor: EmbeddingDescriptor { get }
		func embed(_ texts: [String]) async throws -> [[Double]]
	}

	struct EmbeddingDescriptor: Hashable, Sendable, Codable {
		public var provider: String
		public var model: String
		public var modelRevision: String?
		public var tokenizer: String
		public var dimensions: Int?
		public var normalized: Bool
		public var pooling: String
		public private(set) var identifier: String
	}
}
```

Then let packaging decide which providers exist:

| Package or target | Role |
| --- | --- |
| `Lexicon` | Pure Swift search entries, scoring, traversal, cache format, and provider protocol. |
| `LexiconSearchMLX` | Apple-focused MLX provider. Heavy optional dependency. |
| `LexiconSearchONNX` | ONNX Runtime provider for Linux, Android, Windows, and potentially Apple. Heavy optional dependency. |
| `lexicon` CLI | Provider selection, model/cache paths, and user-facing diagnostics. |

This lets library users inject their own provider without rebuilding Lexicon with every ML stack. The CLI can still have convenience builds. A trait can remain as a packaging shortcut, but it should not be the conceptual model.

## ONNX PoC Sketch

This is deliberately markdown-only. It describes the small spike needed before committing to a production provider.

### 1. Wrap ONNX Runtime C API

Create a C target that exposes `onnxruntime_c_api.h`:

```text
Sources/CLexiconONNXRuntime/include/module.modulemap
Sources/CLexiconONNXRuntime/include/onnxruntime_c_api.h
Sources/CLexiconONNXRuntime/shim.c
```

Example module map:

```c
module CLexiconONNXRuntime {
	header "onnxruntime_c_api.h"
	link "onnxruntime"
	export *
}
```

Linux can link against a downloaded or system-provided `libonnxruntime.so`. Android can unpack the AAR and point the Swift Android build at the matching `jni/<abi>/libonnxruntime.so`. Windows would need the ONNX Runtime DLL and import library on the Swift toolchain's linker path.

### 2. Add a Swift provider target

```swift
public struct ONNXSearchEmbeddingProvider: Lexicon.Search.EmbeddingProvider {
	public var descriptor: Lexicon.Search.EmbeddingDescriptor

	private let runtime: ONNXRuntime
	private let tokenizer: any SearchTokenizerProvider
	private let model: URL

	public init(model: URL, tokenizer: any SearchTokenizerProvider) throws {
		self.model = model
		self.tokenizer = tokenizer
		self.runtime = try ONNXRuntime(model: model)
		self.descriptor = .init(
			provider: "onnxruntime",
			model: model.lastPathComponent,
			modelRevision: nil,
			tokenizer: tokenizer.identifier,
			dimensions: 384,
			normalized: true,
			pooling: "mean"
		)
	}

	public func embed(_ texts: [String]) async throws -> [[Double]] {
		let batch = try tokenizer.encode(texts)
		let outputs = try runtime.run([
			"input_ids": batch.inputIDs,
			"attention_mask": batch.attentionMask,
			"token_type_ids": batch.tokenTypeIDs,
		])
		return meanPool(outputs.lastHiddenState, mask: batch.attentionMask)
			.map(l2Normalize)
	}
}
```

The spike only needs to prove one model, one tokenizer, CPU execution, and deterministic vectors. It should compare a few known query/document cosine scores against Python ONNX Runtime or Transformers output.

### 3. Extend cache keys

The embedding cache should be keyed by a provider descriptor plus document fingerprint. For portable semantic search, that descriptor should include:

- provider name and runtime version
- model id and revision/hash
- tokenizer id and revision/hash
- output dimensions
- pooling and normalization rule
- input prefixes such as `search_query:` and `search_document:`
- graph/search-space fingerprint

If any of those change, cached vectors are not safely reusable.

### 4. Add CI in layers

Start with pure Swift coverage:

```sh
swift test --filter LexiconDocumentSearchTests/test_search_demo_lexicon_examples_are_searchable
```

Then add an ONNX provider job that downloads one tiny model fixture and runs:

```sh
swift test --filter ONNXSearchEmbeddingProviderTests
swift run lexicon search Examples/search-demo.lexicon "late delivery after carrier delay" \
	--mode semantic \
	--embedding-provider onnx \
	--embedding-model .build/models/search-demo/model.onnx
```

Android should come after Linux. First prove the provider can cross-build with the Android Swift SDK and link the ONNX Runtime AAR libraries; then run a small emulator test when the native packaging is stable.

## Recommendation

Keep MLX as an Apple semantic backend, but treat it as one provider, not the search architecture. This branch already exposes the embedding provider abstraction from `Lexicon` and moves the MLX implementation into `LexiconSearchMLX`.

The next implementation step should be:

1. Build a small `LexiconSearchONNX` PoC against one known ONNX sentence-embedding model.
2. Prove the provider on Linux first with a downloaded ONNX Runtime CPU package.
3. Prove Android linking next by unpacking the ONNX Runtime AAR for the matching ABI.
4. Decide whether the CLI should keep traits, expose separate executable products, or support dynamic provider discovery for heavyweight runtimes.
