# Lexicon for VS Code

VS Code language support for Lexicon documents and Lexicon path references in file-backed source documents.

## Features

- `.lexicon` language registration.
- Basic syntax highlighting for Lexicon documents.
- LSP completions and diagnostics through `lexicon-lsp`.
- Lexicon path completions in `.lexicon` documents.
- Lexicon path completions in quoted `l("...")` calls in any file-backed language.
- Lexicon path completions in Rust-style `l!(...)` macros.

## Setup

Build or install `lexicon-lsp` first:

```sh
swift build -c release --product lexicon-lsp
```

If `lexicon-lsp` is not on `PATH`, set the binary path:

```json
{
  "lexicon.lsp.binary.path": "/path/to/lexicon-lsp"
}
```

Then add a workspace config file such as `lexicon-lsp.json`:

```json
{
  "lexicon": "commerce.lexicon"
}
```

Accepted config filenames are `lexicon-lsp.json`, `.lexicon-lsp.json`, `lexicon.conf` and `.lexicon.conf`.

## Development

```sh
npm install
npm test
npm run package
```
