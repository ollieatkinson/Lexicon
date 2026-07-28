# Security Policy

## Supported versions

Security fixes target the latest tagged release and `trunk`. Older 0.x releases may require upgrading because the document format and public API are still evolving.

## Reporting a vulnerability

Use [GitHub private vulnerability reporting](https://github.com/ollieatkinson/Lexicon/security/advisories/new) so maintainers can investigate before details are public.

Include:

- affected commit or release;
- platform and Swift version;
- the smallest reproducer;
- expected and observed behavior;
- security impact and realistic attack preconditions;
- whether untrusted files, imports, generated output, or network access are involved.

If private reporting is unavailable, open a minimal public issue asking for a private contact channel. Do not include exploit code, secrets, sensitive paths, or vulnerable production data in that issue.

No response or remediation SLA is promised. Maintainers will acknowledge a complete private report, assess supported versions, coordinate a fix and disclosure, and credit the reporter unless anonymity is requested.

## Security boundaries

Lexicon processes inputs that may cross trust boundaries:

- TaskPaper and JSON documents;
- local and remote imports;
- LSP workspace files and configuration;
- generated source code and output paths;
- CLI arguments and machine-readable output;
- embedding models and tokenizer dependencies enabled by `MLXSearch`.

Consumers should keep remote imports disabled unless their policy explicitly permits network access. Local resolvers must confine paths to their configured base. Treat generated source as derived from its input documents and review untrusted inputs before compiling it.

Never include credentials in lexicon documents, LSP configuration, generator arguments, fixtures, logs, or vulnerability reproductions.
