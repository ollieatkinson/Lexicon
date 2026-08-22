# Releasing Lexicon

Releases are deliberate compatibility points across Swift APIs, the document format, CLI behavior, generated output, and the canonical wiki.

## Versioning

Lexicon uses semantic version tags. During 0.x development, a minor release may include source or document-format migrations, but every such change must be called out in the versioned migration article. Patch releases must not knowingly introduce new breaking behavior.

## Prepare

1. Choose the release commit on `trunk`.
2. Confirm `Package.swift` products, traits, platform declarations, and dependency constraints are intentional.
3. Update the versioned API contract and migration article.
4. Regenerate and compile representative Swift, Kotlin, Go, Rust, and TypeScript outputs.
5. Confirm CLI help, output schemas, and exit statuses match the wiki contract.
6. Review security-sensitive changes to parsing, import resolution, file output, LSP input, and optional model loading.

## Validate

Run the complete supported matrix, including:

```sh
swift test -Xswiftc -warnings-as-errors
swift test --traits Editor -Xswiftc -warnings-as-errors
swift test \
	-Xswiftc -strict-concurrency=complete \
	-Xswiftc -warnings-as-errors
python3 Scripts/verify_wiki_contract.py
```

Run MLX-specific build/tests on a supported host when that surface changed. Verify Apple compile lanes, Linux tests, tooling integration tests, generated-language compilation, and DocC warnings before tagging.

Do not classify Android as verified unless the release commit has green named emulator or cross-build jobs. Otherwise retain the experimental status.

## Synchronize the canonical wiki

The release gate requires a green live-wiki verification for both the release commit and current wiki commit.

1. Apply every item in the release's companion wiki ledger.
2. Commit the separate wiki checkout.
3. Compare its tagged blocks:

   ```sh
   python3 Scripts/refresh_wiki_contract.py --wiki ../Lexicon.wiki
   ```

4. Refresh the repository-local fixtures and recorded wiki revision:

   ```sh
   python3 Scripts/refresh_wiki_contract.py --wiki ../Lexicon.wiki --write
   python3 Scripts/verify_wiki_contract.py
   ```

5. Commit the mechanical refresh.
6. Record the successful live-wiki workflow URL and both Git SHAs in the release evidence.

Review links required for installation, security reporting, migration, and API access before release. Third-party URL availability is not part of the deterministic wiki-contract workflow.

## API reference

Build DocC with warnings treated as errors. Publish immutable documentation for the release tag and update the `latest` alias only after the tagged site is available. The wiki should link to the versioned API site instead of duplicating symbol declarations.

## Tag and publish

1. Confirm the release commit and worktree are clean.
2. Create an annotated `vMAJOR.MINOR.PATCH` tag.
3. Push the tag.
4. Publish release notes containing:
   - user-visible behavior changes;
   - migration requirements;
   - affected products and traits;
   - document-format or generated-output changes;
   - security fixes, with coordinated disclosure where applicable;
   - links to the migration guide, API reference, and canonical wiki.
5. Verify the tag, source archive, package resolution, release page, and documentation URLs from a clean consumer checkout.

If any published artifact or documentation points at a different commit, stop and correct the release evidence before announcing it.
