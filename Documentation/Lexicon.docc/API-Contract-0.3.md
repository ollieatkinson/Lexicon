# Lexicon 0.3 API Contract

This article defines the intended public behavior for the 0.3 release line. It is a release contract rather than a tutorial. While 0.3 remains unreleased, source on `trunk` may change to complete this contract; a tagged 0.3 release must not contradict it.

## Identity

Lexicon distinguishes three identifier roles:

- `Lemma.Name` is one path component. It begins with a letter or underscore, but `_` alone is invalid. Remaining characters are letters, decimal digits, or single underscores; consecutive underscores are invalid.
- `Lemma.ID` is an absolute dotted path made from valid names.
- `Lemma.RelativeID` is a typed relative path resolved from an explicit context.

APIs must not silently reinterpret one role as another. Parsing malformed identifiers produces diagnostics instead of partially normalizing them.

An in-memory graph node's dictionary key is its identity. It does not carry a second mutable `name` value that can disagree with the key. Serialized node records may carry the name needed to reconstruct that dictionary entry.

## Roots and documents

Root selection is explicit whenever a document can contain more than one root. APIs must not select the first dictionary entry as an implicit root.

Decoding, graph construction, validation, composition, and editing preserve every root in a document. Root-scoped operations identify the intended root in their input or fail without mutation.

Replacing an editor's entire document is an explicit operation. It is not an incidental side effect of resetting one graph.

## Lemma handles

`Lemma` values are immutable, generation-scoped handles:

- A handle identifies one lemma in one materialized generation of one `Lexicon`.
- A successful edit creates a new generation.
- Callers reacquire handles after a successful write.
- A write rejects a stale handle from an earlier generation.
- A write rejects a foreign handle created by another `Lexicon`, even when its textual ID is equal.

Textual IDs remain the durable representation for persistence and process boundaries. A handle is not a durable write capability.

## Editing

Incremental graph-editing APIs—such as add, rename, move, delete, type, and protonym changes—are available only with the `Editor` package trait. Explicit validated replacement of the complete document remains part of the core surface.

Every incremental edit is transactional:

- validation and reference analysis complete before commit;
- failure leaves the editor document, connected lexicon, revision, and existing handles unchanged;
- `Lexicon.Document.Editor` publishes one complete validated document value;
- the corresponding `Lexicon` operation commits that document as one new revision and generation;
- edits are root-aware.

Renaming or moving a subtree rewrites references across every root in the document. Deleting a subtree that is still referenced is rejected. Callers must deliberately remove or redirect those references first.

## Parsing and validation

TaskPaper decoding is strict and single-pass:

- indentation uses tabs;
- malformed indentation is diagnosed rather than guessed;
- duplicate declarations are errors;
- unknown or misplaced metadata is an error;
- root decoding is explicit;
- diagnostics identify the source location and reason.

Validation reports at least:

- malformed or unresolved references;
- invalid synonym structure;
- synonym/type incompatibility;
- canonical type cycles;
- canonical protonym cycles;
- cycles that mix type and protonym relationships.

Validation failure never publishes a partially decoded or partially edited document.

## Composition

Composition uses deterministic last-writer precedence:

1. Document imports are applied in their declared order.
2. Each later import overwrites earlier values at the same path and field.
3. The source document is applied after its imports, so local values win.
4. Node-level imports follow the same rule at their graft point.

Value collisions are not merge conflicts. Import resolution, loading, parsing, and invalid grafts remain diagnostics. A generator consumes the completed overlay and does not fail merely because two inputs declared the same value.

Local import resolution must remain inside its configured base. Remote resolution is opt-in and limited to an explicit consumer policy; CLI and generation do not silently enable network access.

Recursive composition resolves each nested import relative to the document that
declared it. Cycle detection uses canonical source identities supplied by the
resolver, never structural document equality. File-backed callers should pass
the source URL as `FileLexiconImportResolver.rootURL`; custom resolvers that can
identify their starting source should provide `rootIdentity`.

## CRDT behavior

CRDT operations and decode/merge paths are deterministic and atomic:

- Reapplying an operation ID with an identical payload is idempotent.
- Reusing an operation ID with a different payload throws.
- Decode and merge validate the complete candidate before commit.
- A failed decode or merge leaves the previous replica unchanged.
- Missing source dates use the deterministic `unspecifiedDate` value rather than the wall clock.

An operation's node `path` is a stable creation-time address. Renaming that node
or one of its ancestors changes its path in the materialized document, but not
the address used by later operations. `Replica.materialization()` returns the
validated document and the bidirectional lookup needed to translate between
stable node addresses and current materialized paths. Node-to-node references
in operations use stable addresses and are rewritten to current paths during
materialization.

These rules make replay safe and prevent invalid partial replicas.

## Runtime events

`SwiftLexicon.Events` uses observer terminology:

- `on` creates an `EventObserver`.
- `handler` creates an `EventHandler` for operator-based observation.
- `send` is synchronous and throwing, and returns a `SendReceipt`.
- sending after `finish()` throws;
- `finish()` and observer cancellation are idempotent;
- `wait()` suspends until an observer finishes;
- buffering is explicitly unbounded, newest-N, or oldest-N;
- the default is `.oldest(256)`, which retains the oldest 256 pending events for each observer and drops newly sent events while that observer's buffer is full.

`.newest(capacity)` makes the opposite bounded trade-off: it retains the newest pending values and drops the oldest pending value when full. Bounded capacities must be positive.

Generated dotted IDs, not generated Swift type names, are the stable runtime representation.

Direct bracket values are limited to values with an infallible JSON representation. Floating-point and custom `Encodable` values use the throwing `encoding(_:)` path; non-finite floating-point values are rejected by the default encoder.

## Compatibility boundaries

`Lexicon`, `SwiftLexicon`, `LexiconGenerators`, `LexiconSearchMLX`, and `LexiconSearchONNX` are public library products. Their public APIs follow the release's source-compatibility policy.

Embedding descriptors include query and document prefixes because those strings affect cache compatibility. Descriptors decoded from the earlier schema use the legacy `search_query: ` and `search_document: ` prefixes. Providers with model-specific conventions override those defaults, and semantic search never silently reuses a cache produced with different prefix semantics.

Products whose names begin with an underscore are exposed for package implementation and generated-code support. They carry no independent source-compatibility promise unless a release note explicitly says otherwise.

The wiki owns narrative guidance. Source declarations and this versioned contract own symbol and behavioral truth. If an example conflicts with this contract, the example must be corrected and protected by the wiki contract verifier.
