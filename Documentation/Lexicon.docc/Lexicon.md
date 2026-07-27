# ``Lexicon``

Model, validate, compose, inspect, and generate recurrent software vocabularies.

## Overview

Lexicon turns a TaskPaper-like document into a typed semantic graph. The package separates the document model, generated Swift runtime, generators, optional MLX search, command-line tools, and editor integrations so clients can adopt only the layers they need.

The [GitHub wiki](https://github.com/ollieatkinson/Lexicon/wiki) is the canonical source for tutorials, workflows, editor setup, and language-specific generation guides. This catalog describes the versioned API surface and behavioral guarantees that must move with source.

Lexicon 0.3 makes identity, root selection, mutation lifetime, parsing, validation, and CRDT behavior explicit. See <doc:API-Contract-0.3> before building an editor or persistence layer, and <doc:Migration-0.3> when updating a 0.2 client.

## Topics

### API contract

- <doc:API-Contract-0.3>
- <doc:Migration-0.3>

### Package configuration

- <doc:Package-Traits>

### Narrative documentation

- [Quick Start](https://github.com/ollieatkinson/Lexicon/wiki/Quick-Start)
- [Core Concepts](https://github.com/ollieatkinson/Lexicon/wiki/Core-Concepts)
- [Document Syntax](https://github.com/ollieatkinson/Lexicon/wiki/Document-Syntax)
- [Composition and Imports](https://github.com/ollieatkinson/Lexicon/wiki/Composition-and-Imports)
- [CLI Reference](https://github.com/ollieatkinson/Lexicon/wiki/CLI-Reference)
- [Code Generation](https://github.com/ollieatkinson/Lexicon/wiki/Code-Generation)
- [Editor Support](https://github.com/ollieatkinson/Lexicon/wiki/Editor-Support)

> Note: This catalog is staged outside the package targets. Attach or split it into module catalogs when DocC publication is added; do not copy its articles into the wiki.
