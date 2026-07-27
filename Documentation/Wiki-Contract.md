# Wiki Contract

Lexicon keeps narrative documentation in a separate GitHub wiki repository. Pull requests must nevertheless be able to detect code changes that invalidate important examples without depending on the network or on mutable wiki HEAD.

`Documentation/wiki-contract.json` therefore records a small executable contract:

- the reviewed wiki baseline;
- stable page and marker IDs;
- repository-local fixture paths and SHA-256 digests;
- format- or behavior-specific static checks;
- assertions that keep high-risk README claims aligned.

It does not copy whole wiki pages. The fixtures are only the smallest inputs and expected outputs needed for deterministic verification.

## Contract markers

Canonical wiki blocks use an HTML marker immediately before a fenced block:

````markdown
<!-- lexicon-contract:quick-start-commerce -->
```taskpaper
commerce:
```
````

Marker IDs are lowercase ASCII words separated by hyphens. A page may contain many markers, but each page/marker pair must be unique. The fence language and body must match the manifest exactly.

## Verification levels

### Pull requests

`python3 Scripts/verify_wiki_contract.py` reads only the repository checkout. It validates manifest structure, fixture hashes, UTF-8/LF formatting, relative Markdown links, TaskPaper indentation, JSON syntax, selected behavioral invariants, and repository assertions.

This is the required, non-flaky check. It does not clone the wiki, follow external links, download models, or invoke SwiftPM.

### Wiki edits and scheduled checks

GitHub's [`gollum` event](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#gollum), a manual run, and a scheduled run should clone wiki HEAD and execute:

```sh
python3 Scripts/verify_wiki_contract.py --wiki path/to/Lexicon.wiki
```

Tagged content and relative links are hard failures. The scheduled workflow deliberately does not probe external URLs: third-party availability is mutable and must not make the deterministic contract flaky. Review release-critical external links separately before publishing.

### Releases

A release must have a successful live-wiki check for the release commit and the then-current wiki commit. Record both SHAs in the release evidence. This closes the short cross-repository coordination window after a behavior-changing code merge.

## Changing a contract

1. Change code and its repository-local contract fixture together.
2. Run the local verifier.
3. Merge the code change.
4. Apply and commit the companion wiki edit.
5. Run the refresh script without `--write` to inspect differences.
6. Run it with `--write` in the main checkout to copy the canonical blocks and record the wiki SHA.
7. Commit the mechanical manifest/fixture refresh.
8. Require a green live-wiki run before release.

The refresh command stages every wiki block in memory before writing any fixture. It refuses a dirty wiki checkout and never performs network operations.

## Synchronization metadata

`baselineRevision` records the wiki commit from which a coordinated documentation change began. `validatedRevision` records the exact committed wiki content copied into the fixtures. A null validated revision with `companionUpdateRequired: true` means the ledger is pending; a full SHA with `companionUpdateRequired: false` means the tagged blocks were synchronized.

The 0.3 ledger began from wiki revision `7fb0e3318ba02c30419bfaaf4485a964e20ad11b`.
