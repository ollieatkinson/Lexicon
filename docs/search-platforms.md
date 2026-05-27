# Search Platform Support

Lexicon search has a pure Swift core and optional semantic providers:

| Capability | macOS/iOS | Linux | Android | Windows direction |
| --- | --- | --- | --- | --- |
| `token` | Supported | Supported | Supported in library tests | Pure Swift path should work |
| `lexical` | Supported | Supported | Supported in library tests | Pure Swift path should work |
| `hybrid` without embeddings | Supported | Supported | Supported in library tests | Pure Swift path should work |
| `semantic --embedding-provider system` | Uses `NaturalLanguage` | Not available | Not available | Not applicable |
| `semantic --embedding-provider mlx` | Supported with `MLXSearch` | Not promised | Not promised | Not applicable |
| `semantic --embedding-provider onnx` | Supported with `ONNXSearch` | C API path implemented | C API/AAR path implemented | Artifact install exists; session path needs Windows work |

`token`, `lexical`, and non-semantic `hybrid` search are implemented with Lexicon search entries, token scoring, phrase scoring, graph traversal, and bounded resolved context. They do not require `NaturalLanguage`, MLX, ONNX, or a platform ML runtime.

Semantic search is different. The system provider uses Apple's `NaturalLanguage` embeddings, so it only exists where that framework is present. The MLX provider is an Apple-focused backend behind the `MLXSearch` package trait. The portable backend is `LexiconSearchONNX`, which keeps ONNX Runtime behind the `ONNXSearch` trait and the `Lexicon.Search.EmbeddingProvider` abstraction.

## What This Spike Implements

| Area | Status |
| --- | --- |
| Provider abstraction | `Lexicon.Search.EmbeddingProvider` stays in `Lexicon`; MLX and ONNX are optional provider targets. |
| Query/document prefixes | Prefixes live in provider/model configuration and are included in embedding cache identity. |
| Pooling | ONNX supports mean, CLS, and last-token pooling with optional L2 normalization. |
| Model registry | Built-in ONNX presets cover MiniLM, BGE-small, GTE-small, and E5-small-v2. |
| Runtime packaging | SwiftPM command plugin installs ONNX Runtime release artifacts for Linux, Android, and Windows. |
| Non-Apple runtime | `CLexiconONNXRuntime` imports the ONNX Runtime C API and loads the runtime library dynamically on Linux, Android, and Windows builds. |
| Quality harness | `lexicon search-evaluate` runs real searches and reports MRR@10, nDCG@10, recall@10, latency, index time, and cache size. |

The Windows artifact installer is present, but the C API session still needs `ORTCHAR_T` wide-string path bridging before Windows semantic search can run. Linux and Android are the immediate shipping targets.

## Provider Design

The public search design does not depend on SwiftPM traits. Traits are packaging switches for large optional dependencies, not the search abstraction boundary.

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
		public var queryPrefix: String
		public var documentPrefix: String
		public private(set) var identifier: String
	}
}
```

Package targets then decide which providers are available:

| Target | Role |
| --- | --- |
| `Lexicon` | Pure Swift search entries, scoring, traversal, cache format, and provider protocol. |
| `LexiconSearchMLX` | Apple-focused MLX provider. Heavy optional dependency. |
| `LexiconSearchONNX` | Portable ONNX Runtime provider. Heavy optional dependency. |
| `CLexiconONNXRuntime` | Small C shim around ONNX Runtime C API imports and dynamic runtime loading on Linux, Android, and Windows. |
| `lexicon` CLI | Provider selection, model/cache paths, and diagnostics. |

This lets library users inject their own provider without rebuilding Lexicon around every ML stack.

## ONNX Presets

The current presets intentionally use WordPiece/BERT-style tokenizers because that is the tokenizer implemented in this spike. Add more tokenizer implementations when a model requires them.

| Preset | Repository | Revision | Dimensions | Tokenizer | Pooling | Prefixes |
| --- | --- | --- | ---: | --- | --- | --- |
| `all-MiniLM-L6-v2` | `sentence-transformers/all-MiniLM-L6-v2` | `c9745ed1d9f207416be6d2e6f8de32d1f16199bf` | 384 | `wordpiece` | `mean` | none |
| `bge-small-en-v1.5` | `BAAI/bge-small-en-v1.5` | `5c38ec7c405ec4b44b94cc5a9bb96e735b38267a` | 384 | `wordpiece` | `cls` | query instruction |
| `gte-small` | `thenlper/gte-small` | `17e1f347d17fe144873b1201da91788898c639cd` | 384 | `wordpiece` | `mean` | none |
| `e5-small-v2` | `intfloat/e5-small-v2` | `ffb93f3bd4047442299a41ebb6fa998a38507c52` | 384 | `wordpiece` | `mean` | `query: ` / `passage: ` |

## Setup

The setup command is a SwiftPM command plugin, not an external script. SwiftPM command plugins are sandboxed from network access by default, so the command needs `--disable-sandbox`.

Fetch the default model:

```sh
swift package --disable-sandbox --allow-writing-to-package-directory setup-onnx-search-artifacts
```

Fetch a specific model preset:

```sh
swift package --disable-sandbox --allow-writing-to-package-directory setup-onnx-search-artifacts -- \
	--preset bge-small-en-v1.5
```

Fetch Linux x86_64 runtime artifacts:

```sh
swift package --disable-sandbox --allow-writing-to-package-directory setup-onnx-search-artifacts -- \
	--skip-model \
	--runtime linux-x64
LEXICON_ONNX_RUNTIME_PLATFORM=linux-x64 swift build --traits ONNXSearch
```

Fetch Linux arm64 runtime artifacts:

```sh
swift package --disable-sandbox --allow-writing-to-package-directory setup-onnx-search-artifacts -- \
	--skip-model \
	--runtime linux-aarch64
LEXICON_ONNX_RUNTIME_PLATFORM=linux-aarch64 swift build --traits ONNXSearch
```

Fetch Android runtime artifacts:

```sh
swift package --disable-sandbox --allow-writing-to-package-directory setup-onnx-search-artifacts -- \
	--skip-model \
	--runtime android
LEXICON_ONNX_RUNTIME_PLATFORM=android-arm64-v8a swift build --traits ONNXSearch --swift-sdk swift-6.3.1-RELEASE_android
```

The Android installer copies both `android-arm64-v8a` and `android-x86_64` libraries. Set `LEXICON_ONNX_RUNTIME_PLATFORM` to the ABI you are building.

Cross-compilation requires a Swift SDK built with the same Swift compiler version as the host toolchain. If the SDK is older than the local compiler, Swift will fail before Lexicon-specific code finishes compiling.

Fetch Windows x64 artifacts for the next spike:

```sh
swift package --disable-sandbox --allow-writing-to-package-directory setup-onnx-search-artifacts -- \
	--skip-model \
	--runtime windows-x64
```

Windows still needs session path bridging before semantic search can run there.

## CLI Usage

The CLI accepts a preset, a generated `model.json` manifest, or direct local files:

```sh
swift run --traits ONNXSearch lexicon search Examples/search-demo.lexicon \
	"late delivery after carrier delay" \
	--mode semantic \
	--embedding-provider onnx \
	--embedding-model-preset all-MiniLM-L6-v2
swift run --traits ONNXSearch lexicon search Examples/search-demo.lexicon \
	"late delivery after carrier delay" \
	--mode semantic \
	--embedding-provider onnx \
	--embedding-model-manifest .build/onnx-search/all-MiniLM-L6-v2/model.json
swift run --traits ONNXSearch lexicon search Examples/search-demo.lexicon \
	"late delivery after carrier delay" \
	--mode semantic \
	--embedding-provider onnx \
	--embedding-model .build/onnx-search/all-MiniLM-L6-v2/model.onnx \
	--embedding-vocabulary .build/onnx-search/all-MiniLM-L6-v2/vocab.txt
```

The first semantic search for a document creates the embedding cache and logs indexing progress to stderr. The old `warm-search` and `index-search` commands are intentionally not present; first search auto-indexes when needed.

## Quality Harness

`Examples/search-quality.json` contains judgment suites for the demo lexicon plus local Sky and Blockchain lexicons:

```sh
swift run lexicon search-evaluate Examples/search-quality.json \
	--mode hybrid \
	--embedding-provider none \
	--limit 10
```

For semantic model comparison, run the same judgments with ONNX:

```sh
swift run --traits ONNXSearch lexicon search-evaluate Examples/search-quality.json \
	--mode semantic \
	--embedding-provider onnx \
	--embedding-model-preset bge-small-en-v1.5 \
	--limit 10
```

Use the reported MRR@10, nDCG@10, recall@10, per-query latency, index time, and cache size to choose a default model. Do not pick a model by leaderboard alone; use the local Sky/blockchain/demo judgments because Lexicon search has graph structure and domain terms that generic embedding benchmarks do not measure.

Current local snapshot over `Examples/search-quality.json`:

| Mode/provider | Preset | MRR@10 | nDCG@10 | Recall@10 |
| --- | --- | ---: | ---: | ---: |
| `hybrid` / `none` | none | 0.9583 | 0.9527 | 0.8333 |
| `semantic` / `onnx` | `all-MiniLM-L6-v2` | 0.6694 | 0.6747 | 0.7778 |
| `semantic` / `onnx` | `bge-small-en-v1.5` | 0.9583 | 0.8640 | 0.8889 |
| `semantic` / `onnx` | `gte-small` | 0.9028 | 0.8191 | 0.8889 |
| `semantic` / `onnx` | `e5-small-v2` | 0.8611 | 0.8287 | 0.8611 |

BGE is the strongest semantic default candidate in this small local harness. The default search mode should still stay `hybrid` because token and lexical scoring carry exact graph names better than embeddings alone.

## Cache Identity

The embedding cache is keyed by the provider descriptor and document search fingerprint. For semantic search, the descriptor includes:

- provider name and runtime version
- model id and revision/hash
- tokenizer id and revision/hash
- output dimensions
- pooling and normalization rule
- query and document prefixes
- document search-space fingerprint

If any of those change, cached vectors are not safely reusable.

## Remaining Work

Before calling ONNX search stable, add CI jobs that install runtime artifacts and build the semantic provider on Linux and Android. Keep normal PR checks focused on pure Swift search so review latency stays low.

The main model-correctness gaps after this spike are:

- tokenizer expansion beyond WordPiece for models that need SentencePiece, Unigram, or custom tokenizers
- measured preset comparison from `search-evaluate` over local judgments
- Windows `ORTCHAR_T` path bridging and runtime loading validation
- optional ONNX Runtime Mobile/reduced builds for app-size-sensitive Android deployments
