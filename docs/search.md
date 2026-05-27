# Search

Lexicon search has four user-facing modes, but they are best treated as lenses over the same search entries:

| Mode | Use it for |
| --- | --- |
| `hybrid` | Default search. Combines path/name token matches, phrase matches, metadata, references, and semantic scores when embeddings are available. |
| `semantic` | Natural-language meaning search. Best with `--embedding-provider mlx` and a cached embedding index. |
| `token` | Deterministic path, name, type, default, and reference lookup. Useful for editor tooling and exact-ish IDs. |
| `lexical` | Phrase and fuzzy text search over IDs, notes, comments, defaults, and metadata without synonym rules. |

Scopes decide which graph is searched:

| Scope | Search space |
| --- | --- |
| `own` | The declared document graph only. Fastest and most predictable. |
| `live` | Search `own` first, then expand likely hits through resolved lemma context. Good for interactive search over inherited context. |
| `full` | Materialize the resolved lemma search space, then search it. Traversal counts depth and budget at each child edge and stops repeated inherited structure so recursive types do not expand forever. |

`--depth`, `--candidates`, and `--budget` bound `live` and `full` traversal. The default `hybrid` + `own` path is the simplest starting point.

All examples below use [`Examples/search-demo.lexicon`](../Examples/search-demo.lexicon). For deterministic non-semantic runs:

```sh
swift run lexicon search Examples/search-demo.lexicon submit order --mode hybrid --limit 5 --embedding-provider none
```

For MLX semantic runs:

```sh
swift run --traits MLXSearch lexicon search Examples/search-demo.lexicon "customer asks for money back after purchase" \
	--mode semantic \
	--embedding-provider mlx \
	--embedding-model TaylorAI/bge-micro-v2
```

The first MLX semantic search writes a local embedding cache and logs indexing progress to stderr. The semantic examples below were generated with `TaylorAI/bge-micro-v2`; another model can rank close matches differently.

For ONNX semantic runs, first fetch a model fixture through the package plugin. The default preset is `all-MiniLM-L6-v2`:

```sh
swift package --disable-sandbox --allow-writing-to-package-directory setup-onnx-search-artifacts
swift run --traits ONNXSearch lexicon search Examples/search-demo.lexicon "late delivery after carrier delay" \
	--mode semantic \
	--embedding-provider onnx \
	--limit 3
```

The setup command also accepts `--preset`, `--manifest`, or explicit Hugging Face artifact fields:

```sh
swift package --disable-sandbox --allow-writing-to-package-directory setup-onnx-search-artifacts -- \
	--preset all-MiniLM-L6-v2
swift package --disable-sandbox --allow-writing-to-package-directory setup-onnx-search-artifacts -- \
	--preset bge-small-en-v1.5
swift package --disable-sandbox --allow-writing-to-package-directory setup-onnx-search-artifacts -- \
	--repository sentence-transformers/all-MiniLM-L6-v2 \
	--revision c9745ed1d9f207416be6d2e6f8de32d1f16199bf \
	--model-path onnx/model.onnx \
	--vocabulary-path vocab.txt \
	--id all-MiniLM-L6-v2
```

For Linux or Android ONNX runs, install the matching runtime artifact through the same plugin:

```sh
swift package --disable-sandbox --allow-writing-to-package-directory setup-onnx-search-artifacts -- \
	--skip-model \
	--runtime linux-x64
LEXICON_ONNX_RUNTIME_PLATFORM=linux-x64 swift build --traits ONNXSearch

swift package --disable-sandbox --allow-writing-to-package-directory setup-onnx-search-artifacts -- \
	--skip-model \
	--runtime android
LEXICON_ONNX_RUNTIME_PLATFORM=android-arm64-v8a swift build --traits ONNXSearch --swift-sdk swift-6.3.1-RELEASE_android
```

The CLI can then use a preset, a generated `model.json` manifest, or direct local paths:

```sh
swift run --traits ONNXSearch lexicon search Examples/search-demo.lexicon "late delivery after carrier delay" \
	--mode semantic \
	--embedding-provider onnx \
	--embedding-model-preset all-MiniLM-L6-v2
swift run --traits ONNXSearch lexicon search Examples/search-demo.lexicon "late delivery after carrier delay" \
	--mode semantic \
	--embedding-provider onnx \
	--embedding-model-manifest .build/onnx-search/all-MiniLM-L6-v2/model.json
swift run --traits ONNXSearch lexicon search Examples/search-demo.lexicon "late delivery after carrier delay" \
	--mode semantic \
	--embedding-provider onnx \
	--embedding-model .build/onnx-search/all-MiniLM-L6-v2/model.onnx \
	--embedding-vocabulary .build/onnx-search/all-MiniLM-L6-v2/vocab.txt
```

See [`search-platforms.md`](search-platforms.md) for Linux, Android, Windows, and ONNX backend notes.

## Quality Harness

Search quality should be measured against local judgments, not guessed from generic model leaderboards. [`Examples/search-quality.json`](../Examples/search-quality.json) includes demo, Sky, and Blockchain query suites:

```sh
swift run lexicon search-evaluate Examples/search-quality.json \
	--mode hybrid \
	--embedding-provider none \
	--limit 10
swift run --traits ONNXSearch lexicon search-evaluate Examples/search-quality.json \
	--mode semantic \
	--embedding-provider onnx \
	--embedding-model-preset bge-small-en-v1.5 \
	--limit 10
```

The output reports MRR@10, nDCG@10, recall@10, per-query latency, document load time, index time, and cache size.

## Hybrid Examples

| Query | Top result |
| --- | --- |
| `submit order` | `demo.api.order.submit` |
| `payment decline` | `demo.ui.checkout.error.payment_declined` |
| `free shipping` | `demo.feature.campaign.free_shipping` |
| `refund status` | `demo.api.refund.status` |
| `customer loyalty` | `demo.api.customer.loyalty` |
| `delivery delay` | `demo.analytics.event.delivery_delayed` |
| `checkout button` | `demo.ui.checkout.button` |
| `low stock badge` | `demo.ui.product.card.badge.low_stock` |
| `escalate urgent payment` | `demo.support.ticket.escalate` |
| `purchase completed event` | `demo.analytics.event.purchase_completed` |
| `guest checkout` | `demo.feature.checkout.guest` |
| `seasonal recommendation` | `demo.feature.recommendation.seasonal` |

## Semantic Examples

| Query | Top result |
| --- | --- |
| `customer asks for money back after purchase` | `demo.api.refund.request` |
| `late delivery after carrier delay` | `demo.fulfillment.delivery.delay` |
| `card issuer rejected transaction` | `demo.api.payment.decline` |
| `popular products recommendation` | `demo.feature.recommendation.trending` |
| `holiday weather products` | `demo.feature.recommendation.seasonal` |
| `lapsed customers returning offer` | `demo.feature.campaign.winback` |
| `basket threshold delivery cost` | `demo.feature.campaign.free_shipping` |
| `reserve funds with card issuer` | `demo.api.payment.authorize` |
| `stock availability nearly sold out` | `demo.api.inventory.stock` |
| `inventory reservation during checkout` | `demo.api.inventory.reservation` |
| `help article checkout delivery questions` | `demo.support.knowledge_base.article` |
| `product description benefits fit materials` | `demo.content.product.description` |

## Token Examples

| Query | Top result |
| --- | --- |
| `demo api order submit` | `demo.api.order.submit` |
| `demo api payment decline` | `demo.api.payment.decline` |
| `demo ui checkout button primary` | `demo.ui.checkout.button.primary` |
| `demo ui product card badge low stock` | `demo.ui.product.card.badge.low_stock` |
| `demo analytics event checkout started` | `demo.analytics.event.checkout_started` |
| `demo support ticket status` | `demo.support.ticket.status` |
| `demo fulfillment warehouse ship` | `demo.fulfillment.warehouse.ship` |
| `demo feature checkout save card` | `demo.feature.checkout.save_card` |
| `demo content campaign email` | `demo.content.campaign.email` |
| `demo type component banner` | `demo.type.component.banner` |
| `demo type channel push` | `demo.type.channel.push` |
| `demo api inventory reservation` | `demo.api.inventory.reservation` |

## Lexical Examples

| Query | Top result |
| --- | --- |
| `card issuer rejected the transaction` | `demo.api.payment.decline` |
| `urgent billing or payment issues` | `demo.support.ticket.escalate` |
| `late delivery notification` | `demo.fulfillment.delivery.delay` |
| `support agents` | `demo.api.order.status` |
| `customer submits an order` | `demo.api.order.submit` |
| `carrier pickup to delivery` | `demo.fulfillment.delivery.tracking` |
| `quantity is limited` | `demo.ui.product.card.badge.low_stock` |
| `save payment method for a future checkout` | `demo.feature.checkout.save_card` |
| `shopper search query` | `demo.analytics.event.search_performed` |
| `returning shopper offer` | `demo.feature.campaign.winback` |
| `email and push messages` | `demo.ui.account.settings.notifications` |
| `basket threshold delivery cost` | `demo.feature.campaign.free_shipping` |
