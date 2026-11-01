# Contributing to Lexicon

Thank you for improving Lexicon. The project treats document semantics, generated output, CLI automation, and editor behavior as compatibility surfaces, so changes should include evidence at the layer they affect.

## Requirements

- Swift 6.3
- macOS 15 or a current Linux distribution supported by Swift 6.3
- Git
- Python 3.9 or newer for documentation-contract verification

Additional generator or editor work may require the target language toolchain or Node.js. Keep optional toolchains out of unrelated workflows.

## Before changing code

1. Read the relevant source and tests; do not infer behavior from the wiki alone.
2. Check [`Documentation/Lexicon.docc/API-Contract-0.3.md`](Documentation/Lexicon.docc/API-Contract-0.3.md) for accepted 0.3 invariants.
3. Decide whether the change affects default, `Editor`, `MLXSearch`, or `ONNXSearch` builds.
4. For user-visible behavior, identify the companion wiki page and any fixture in `Documentation/wiki-contract.json`.

The [GitHub wiki](https://github.com/ollieatkinson/Lexicon/wiki) is canonical for narrative documentation. Public API contracts and migrations stay versioned with source.

## Build and test

Run the narrowest relevant tests while iterating, then the supported matrix before requesting review:

```sh
swift test -Xswiftc -warnings-as-errors
swift test --traits Editor -Xswiftc -warnings-as-errors
swift test \
	-Xswiftc -strict-concurrency=complete \
	-Xswiftc -warnings-as-errors
python3 Scripts/verify_wiki_contract.py
```

On a supported MLX host, changes to semantic search also require:

```sh
swift build --traits MLXSearch --product lexicon
```

ONNX provider changes also require the downstream integration build and, on Linux, the runtime-backed tests after installing the pinned artifacts:

```sh
swift package --disable-sandbox --allow-writing-to-package-directory \
	setup-onnx-search-artifacts -- --runtime linux-x64
swift test --traits ONNXSearch -Xswiftc -warnings-as-errors
swift test --package-path IntegrationTests/ONNX
```

Generator changes should generate into a temporary directory and compile the affected language outputs when that toolchain is available. LSP and CLI changes should test the built process, exit status, stdout, and stderr—not only internal functions.

Do not commit incidental dependency-resolution changes. Review `Package.resolved` separately whenever a command modifies it.

## Source expectations

- Preserve Swift 6 strict-concurrency correctness.
- Keep operations deterministic; avoid wall-clock, locale, dictionary-order, model, or network dependence unless the API explicitly requires it.
- Make document edits and CRDT operations atomic.
- Treat identifiers and roots explicitly.
- Add regression tests for public behavior and malformed inputs.
- Use tabs in Swift and TaskPaper examples, matching the existing source style.
- Avoid adding compatibility promises to underscored support products.

## Documentation changes

Repository-local verification is deliberately network-free:

```sh
python3 Scripts/verify_wiki_contract.py
```

If a code change alters a tagged wiki example:

1. Update the local fixture and its manifest digest in the code pull request.
2. Merge the code change.
3. Apply the narrative change in the separate wiki repository.
4. Commit the wiki.
5. Refresh the local contract from that clean checkout.
6. Require a green live-wiki check before release.

See [`Documentation/Wiki-Contract.md`](Documentation/Wiki-Contract.md) for commands and the cross-repository consistency model.

## Pull requests

Keep each pull request focused. Its description should state:

- the behavior being changed;
- the compatibility or migration effect;
- the products and traits affected;
- the validation commands run;
- any required wiki companion edit.

Reviewers should be able to distinguish implementation changes, generated changes, and documentation-contract changes. Do not mix unrelated formatting or dependency updates into a behavioral patch.
