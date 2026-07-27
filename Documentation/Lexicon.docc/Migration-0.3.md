# Migrating from 0.2 to 0.3

Lexicon 0.3 hardens identity, parsing, editing, validation, replay, and runtime events. Plan this as a source migration for clients that edit graphs, retain lemma objects, decode permissive TaskPaper, or observe `SwiftLexicon` events.

## 1. Choose package traits deliberately

Read-only parsing, graph traversal, validation, and generation remain in the default package surface.

Incremental graph-editing APIs now require the `Editor` trait. Enable it in editor applications and run the editor-specific test lane:

```sh
swift test --traits Editor
```

MLX-backed semantic search remains opt-in through `MLXSearch`. Do not enable it for consumers that only need deterministic lexical/token search.

## 2. Migrate identifier values

Replace loosely typed strings at API boundaries with the appropriate identifier role:

- use `Lemma.Name` for one component;
- use `Lemma.ID` for an absolute dotted path;
- use `Lemma.RelativeID` only with an explicit resolution context.

Reject invalid input instead of normalizing it. In particular, names begin with a letter or underscore, `_` alone is invalid, and consecutive underscores are invalid.

If code reads or writes a node's `name`, migrate to the containing dictionary key. In 0.3 the key is the single source of node identity.

## 3. Select roots explicitly

Audit every document-to-graph conversion. Pass or derive the intended root explicitly; do not depend on dictionary ordering.

For multi-root tools, carry the root identity through inspect, edit, validate, and persistence operations. A missing or ambiguous root is an error.

## 4. Stop retaining writable lemma objects

Treat a `Lemma` as an immutable handle for one materialized generation:

1. Resolve a handle.
2. Perform one transactional edit.
3. Discard prior handles.
4. Resolve fresh handles from the resulting `Lexicon`.

Writes with stale or foreign handles now fail. Persist `Lemma.ID` when identity must outlive a generation or cross a process boundary.

## 5. Handle edits transactionally

Update editor flows to surface write failures instead of assuming mutation:

- rename and move may rewrite references in every root;
- deletion fails while any root still references the subtree;
- validation failure leaves the previous generation intact;
- replacing the complete document is a distinct operation.

Remove UI logic that repairs partially applied edits; 0.3 either commits the whole edit or commits nothing.

## 6. Fix TaskPaper sources

Run 0.3 validation over every checked-in `.lexicon` file. Correct:

- space indentation—use tabs;
- duplicate declarations;
- unknown metadata markers;
- metadata attached at an invalid scope;
- malformed absolute or relative identifiers;
- implicit or ambiguous root assumptions.

Do not use plain-text-outline tolerance for canonical Lexicon documents.

## 7. Adopt deterministic composition

If multiple inputs write the same path or field, 0.3 applies imports in declaration order and then applies the source document. Later imports beat earlier imports; local source values beat every import.

Remove code that expects value collisions to appear in `MergePlan.conflicts`. Continue handling resolution, loading, parse, and graft diagnostics.

Review import order explicitly during migration because reordering imports is now a semantic change.

When composing a file-backed root, initialize
`FileLexiconImportResolver` with both its allowed `baseURL` and the source
`rootURL`. Custom recursive resolvers should expose stable source identities and
implement contextual resolution so nested relative imports are resolved from
the declaring document rather than the process working directory.

Remote imports remain opt-in. `FileLexiconImportResolver` accepts at most 1 MiB
per remote response and cancels a streamed response as soon as that limit would
be exceeded. Hosts must serve larger lexicons through an application-specific
resolver with an explicit size policy.

## 8. Update validation handling

Treat unresolved references, invalid synonym structure, synonym/type mismatches, and canonical type/protonym/mixed cycles as invalid input.

CLI automation should use the documented exit status rather than searching diagnostic text. `validate` and `lint` operate on composed input by default; use `--source-only` only when intentionally inspecting one file in isolation.

## 9. Update runtime event observation

Replace 0.2 event vocabulary as follows:

| 0.2 spelling | 0.3 spelling |
| --- | --- |
| `subscribe` | `on` |
| subscription value | `EventObserver` |
| subscription set builder | `EventObserverSetBuilder` |
| `events.then { … }` | `events.handler { … }` |
| `await events.send(event).value` | `try events.send(event)` |

Retain the observer for as long as delivery is required. Call `cancel()` for early termination, or `wait()` when another task must observe completion. Handle `Events.Error.finished` when a producer can race with shutdown.

The default buffer is `.oldest(256)`: each observer retains its oldest 256 pending events and drops newly sent events while full. Choose `.newest`, `.oldest`, or `.unbounded` explicitly if that loss policy is part of application behavior.

Use `try lemma.encoding(value)` for floating-point and custom `Encodable` event values. Direct bracket values are reserved for infallibly representable JSON primitives, and the default encoder rejects NaN and infinity. Arbitrary `Event.Value` JSON uses a throwing bracket subscript, such as `try lemma[json]`, which validates nested arrays and objects before constructing an event.

## 10. Audit CRDT replay

Operation IDs may be replayed only with the same payload. Treat an ID reused with a different payload as corruption or a producer bug.

Remove tests that depend on the current date being synthesized for missing document dates. The deterministic fallback is `unspecifiedDate`.

Treat node `path` values in CRDT operations as stable creation-time addresses,
not paths that follow renames. Code that starts from a current document path
should use `Replica.materialization().nodeAddress(forMaterializedPath:)` before
creating a later operation. Use
`materializedPath(forNodeAddress:)` when presenting an operation address in the
current document.

## 11. Review generated and JSON integrations

Regenerate checked-in source with the 0.3 generator before comparing application changes. Graph JSON now carries ordered reference metadata, and generator type prefixes are configurable. Do not hand-edit generated declarations to retain 0.2 naming.

Compile generated outputs in every language consumed by the project rather than relying only on text snapshots.

## Migration completion

- All canonical TaskPaper inputs pass strict decoding and validation.
- Every multi-root conversion selects a root.
- Editor targets enable `Editor`; read-only targets do not.
- No writable lemma handle survives a successful edit.
- Composition precedence tests cover overlapping imports and a local override.
- Runtime code contains no `subscribe`, `events.then`, or `await events.send(...).value`.
- CRDT replay tests cover identical and conflicting operation-ID reuse.
- Generated sources are refreshed and compiled.
- The canonical wiki companion ledger has been applied and live verification is green.
