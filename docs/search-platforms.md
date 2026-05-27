# Search Platform Support

Lexicon search has two portability stories:

| Capability | macOS/iOS | Linux | Android | Windows direction |
| --- | --- | --- | --- | --- |
| `token` | Supported | Supported | Supported in library tests | Should be pure Swift |
| `lexical` | Supported | Supported | Supported in library tests | Should be pure Swift |
| `hybrid` without embeddings | Supported | Supported | Supported in library tests | Should be pure Swift |
| `semantic --embedding-provider system` | Uses `NaturalLanguage` | Not available | Not available | Not applicable |
| `semantic --embedding-provider mlx` | Supported with `MLXSearch` | Not promised | Not promised | Not applicable |
| `semantic --embedding-provider onnx` | Experimental with `ONNXSearch` | Needs a Linux runtime package path | Needs AAR/ABI packaging | Needs DLL/import-library packaging |

`token`, `lexical`, and non-semantic `hybrid` search are implemented with Lexicon's own search entries, tokenizer, phrase scoring, and traversal logic. They do not require `NaturalLanguage`, MLX, ONNX, or a platform ML runtime.

Semantic search is different. The current lightweight system provider uses `NLEmbedding`, so it only exists where Apple's `NaturalLanguage` framework is present. The optional MLX provider is behind the `MLXSearch` package trait and works well on Apple platforms, but it should not be treated as the Linux or Android plan. `mlx-swift` has Linux work in its manifest, but the embedder stack used here (`mlx-swift-lm` and `swift-hf-api-mlx`) currently declares Apple platforms. That makes MLX a good Apple backend and a poor portability foundation.

## Current Gaps

| Gap | Impact | Needed work |
| --- | --- | --- |
| No fully portable semantic runtime | Linux and Android can run lexical/token search. The ONNX spike proves the provider shape with SwiftPM-resolved ONNX Runtime on Apple platforms, but Linux/Android still need runtime packaging. | Add a non-Apple ONNX Runtime link path. |
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

## Current ONNX Spike

`LexiconSearchONNX` is implemented as a real root package target behind the `ONNXSearch` trait. It uses Microsoft's `onnxruntime-swift-package-manager` dependency, so ONNX Runtime itself is resolved by SwiftPM instead of a shell script. The provider currently uses:

- `Sources/LexiconSearchONNX/ONNXSearchEmbeddingProvider.swift`
- `Sources/LexiconSearchONNX/ONNXRuntimeSession.swift`
- `Sources/LexiconSearchONNX/WordPieceSearchTokenizer.swift`
- `Sources/LexiconSearchONNX/ONNXPooling.swift`

The MiniLM model fixture is fetched by a Swift package command plugin:

```sh
swift package --disable-sandbox --allow-writing-to-package-directory setup-onnx-search-artifacts
```

SwiftPM command plugins are sandboxed from network access by default, so `--disable-sandbox` is needed for the Hugging Face download. The plugin writes the pinned model and vocabulary to `.build/onnx-search/all-MiniLM-L6-v2`.

Build and test:

```sh
swift build --traits ONNXSearch
swift test --traits ONNXSearch
swift run --traits ONNXSearch lexicon search Examples/search-demo.lexicon \
	"late delivery after carrier delay" \
	--mode semantic \
	--embedding-provider onnx \
	--limit 3
```

The provider embeds with `sentence-transformers/all-MiniLM-L6-v2`, WordPiece tokenization, attention-mask mean pooling, and L2 normalization.

## Cache Identity

The embedding cache should be keyed by a provider descriptor plus document fingerprint. For portable semantic search, that descriptor should include:

- provider name and runtime version
- model id and revision/hash
- tokenizer id and revision/hash
- output dimensions
- pooling and normalization rule
- input prefixes such as `search_query:` and `search_document:`
- graph/search-space fingerprint

If any of those change, cached vectors are not safely reusable.

## Remaining Portability Work

The current ONNX spike proves the target and CLI abstraction, but it does not finish Linux/Android/Windows support. The Microsoft SwiftPM package currently exposes Apple platform bindings. Portable support should come in layers:

- Linux: add a C target that exposes `onnxruntime_c_api.h` and links a downloaded or system-provided `libonnxruntime.so`.
- Android: unpack `onnxruntime-android` from Maven Central and pass the matching `jni/<abi>/libonnxruntime.so` to the Swift Android build.
- Windows: add an ONNX Runtime DLL/import-library path and handle `ORTCHAR_T` model paths.
- CI: keep pure Swift search in normal PR checks; add ONNX semantic jobs only where runtime artifacts are intentionally installed.

## Recommendation

Keep MLX as an Apple semantic backend, but treat it as one provider, not the search architecture. This branch already exposes the embedding provider abstraction from `Lexicon` and moves the MLX implementation into `LexiconSearchMLX`.

The next implementation step should be:

1. Keep the current SwiftPM-backed `LexiconSearchONNX` target as the Apple/CLI proof.
2. Add the Linux C-runtime target without changing `SearchEmbeddingProvider`.
3. Prove Android linking by unpacking the ONNX Runtime AAR for one ABI.
4. Decide whether heavyweight providers stay behind traits or become separate products/packages.
