# 0.3 Wiki Companion Change Ledger

This ledger targets the separate wiki baseline `7fb0e3318ba02c30419bfaaf4485a964e20ad11b`. It is intentionally not applied by the code change. Complete every item in one coordinated wiki update, then refresh `Documentation/wiki-contract.json`.

## Contract-block edits

1. **`Quick-Start.md`**
   - Add `<!-- lexicon-contract:quick-start-commerce -->` immediately before the TaskPaper block currently beginning at line 38.
   - Replace that block with `Documentation/WikiContract/Fixtures/quick-start-commerce.lexicon`.
   - Add `<!-- lexicon-contract:quick-start-lsp -->` before the LSP JSON block currently beginning at line 115 and replace it with `quick-start-lsp.json`.
   - State that generation creates missing output parent directories only after that behavior is present in the released generator; otherwise add `mkdir -p Generated`.
   - Describe quoted `l("…")` references as available in any file-backed language, not only Go.

2. **`Composition-and-Imports.md`**
   - Replace the “Conflicts” section currently around lines 100–108. The contract is: imports apply in document order; each later import overwrites earlier values at the same path/field; the source document is applied last and wins; value collisions are not conflicts; resolution/loading/parse failures remain diagnostics.
   - Add the three marked TaskPaper blocks `composition-base`, `composition-overlay`, and `composition-root` using the matching fixtures.
   - Add the marked JSON block `composition-expected` and explain why its final value is `"local"`.
   - Remove the claim that generation fails because two documents provide incompatible metadata.
   - Clarify whether nested imports are resolved relative to each importing document after the resolver implementation is finalized; do not claim this before code and tests establish it.

3. **`CLI-Reference.md`**
   - Add `<!-- lexicon-contract:cli-validation-contract -->` before a new JSON automation-contract block populated from `cli-validation-contract.json`.
   - State that `validate` and `lint` operate on the composed document by default, `--source-only` opts out, valid input exits `0`, and invalid input exits `1`. JSON results and document diagnostics use stdout; usage and command-execution errors use stderr.
   - Generate command/option tables from normalized `--help` output. Include `remove`, clear modes, generator `--quiet`, Go package naming, class/protocol prefixes, defaults, and exit behavior.
   - Do not claim warning-only lint fails unless the shipped strictness contract makes it invalid.

4. **`Runtime-Events.md`**
   - Rewrite all code blocks using the 0.3 observer vocabulary.
   - Add `<!-- lexicon-contract:runtime-events-basic -->` before the first Swift block and replace it with `runtime-events-basic.swift`.
   - Replace `subscribe` with `on`, `Subscription` with `Observer`/`EventObserver`, and `then` with `handler`.
   - Show synchronous throwing `send`, its `SendReceipt`, `cancel()`, `wait()`, idempotent `finish()`, and buffering policies. State exactly that the default `.oldest(256)` retains the oldest 256 pending events per observer and drops newly sent events while full; contrast it with `.newest`.
   - Remove every `await events.send(...).value` example.

## Narrative corrections

5. **`Language-Swift.md`**
   - Replace runtime event examples around lines 103–121 with the same `on`/`handler`/throwing `send` vocabulary.
   - Link to the 0.3 runtime API reference rather than maintaining a second complete event tutorial.

6. **`Editor-VS-Code.md`**
   - Replace the opening claim and thin-client tutorial around lines 3–116 with the existing first-party extension.
   - Document its actual binary-path, arguments, and environment settings; workspace-build/PATH discovery; restart and output commands; and all-file-backed document selector.
   - Retain generic TypeScript client code only under a clearly labelled third-party-client section.

7. **`Editor-Support.md`**
   - Replace the support summary around lines 97–100: VS Code is first-party, while Zed, JetBrains, and other clients use LSP configuration.
   - State that quoted-call completion is language-neutral for file-backed documents, with Rust macro syntax as an additional form.

8. **`Platform-Support.md`**
   - Replace unconditional Android claims around lines 3 and 24–38 with a four-column matrix: declared, compile-tested, test-executed, and notes.
   - macOS and Linux may be described as CI-tested when their jobs are green.
   - iOS may be described only at the level actually exercised by CI.
   - Android is experimental and currently unverified; remove emulator and ARM64 cross-build claims until named jobs exist and remain green.

9. **`Language-TypeScript.md`**
   - Do not show `import { commerce }` unless generated TypeScript exports that root and the example passes `tsc`.
   - Once named exports ship, show the exact emitted module form and compiler command; otherwise describe the generated file as a global script.

10. **`Language-Kotlin.md`**
    - Remove the localized-display example around lines 27–45 while generated `.localized` remains empty.
    - Demonstrate identifiers and typed paths, or explicitly document the placeholder and the application-owned localization adapter.

11. **`Code-Generation.md`**
    - Replace the same-extension collision warning with exact preflight behavior once implemented.
    - Remove the claim that value collisions during composition necessarily abort generation.
    - Document output-parent creation only after a test protects it.

12. **`Document-Syntax.md`**
    - Add the complete 0.3 identifier grammar: a component begins with a letter or underscore, `_` alone is invalid, then uses letters, decimal digits, or single underscores; consecutive underscores are invalid.
    - Document tabs-only indentation and explicit diagnostics for duplicates and unknown or misplaced metadata.
    - Distinguish absolute dotted IDs, single-component names, and relative IDs.

13. **`Troubleshooting.md`**
    - Align import-base guidance with the final resolver contract.
    - Explain that remote imports are disabled by default in CLI/generation and may be enabled only by an explicit consumer policy.
    - Replace advice based on composition value conflicts with last-import-wins diagnostics.

14. **Wiki navigation and API links**
    - Add a “Migrating to 0.3” entry that links to the versioned migration article when published.
    - Link narrative concept pages to versioned DocC API reference pages rather than copying signatures.
    - Mark the wiki as the canonical narrative source and the generated DocC site as the canonical symbol reference.

## Completion commands

After committing the wiki changes:

```sh
python3 Scripts/refresh_wiki_contract.py --wiki ../Lexicon.wiki
python3 Scripts/refresh_wiki_contract.py --wiki ../Lexicon.wiki --write
python3 Scripts/verify_wiki_contract.py
```

The first command must be expected to report differences before refresh. The second must set `validatedRevision` to the committed wiki SHA and `companionUpdateRequired` to `false`. The final local verification and live `gollum` workflow must both pass before a 0.3 release.
