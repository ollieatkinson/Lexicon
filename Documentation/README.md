# Repository Documentation

The [GitHub wiki](https://github.com/ollieatkinson/Lexicon/wiki) is the canonical source for Lexicon's narrative documentation: tutorials, concepts, CLI workflows, language guides, editor setup, examples, and troubleshooting.

This directory contains documentation that must remain versioned with the code:

- [`Lexicon.docc/Lexicon.md`](Lexicon.docc/Lexicon.md) is the staged package API landing page.
- [`Lexicon.docc/API-Contract-0.3.md`](Lexicon.docc/API-Contract-0.3.md) records the public 0.3 behavioral contract.
- [`Lexicon.docc/Migration-0.3.md`](Lexicon.docc/Migration-0.3.md) is the source migration checklist from 0.2.
- [`Lexicon.docc/Package-Traits.md`](Lexicon.docc/Package-Traits.md) records products, traits, and availability.
- [`Wiki-Contract.md`](Wiki-Contract.md) explains deterministic wiki verification.
- [`Wiki-Companion-Ledger-0.3.md`](Wiki-Companion-Ledger-0.3.md) records the coordinated 0.3 companion changes for the separate wiki repository.

The DocC catalog is intentionally staged under `Documentation/`. It can be attached to package targets once module-level API comments and documentation hosting are introduced. Until then, the Markdown remains reviewable without changing target membership.

## Authority

| Information | Authoritative source |
| --- | --- |
| Tutorials, workflows, examples, and troubleshooting | GitHub wiki |
| Public symbol signatures and availability | Swift source and `Package.swift` |
| Public behavioral guarantees and migration notes | DocC articles in this directory |
| CLI spellings and defaults | Executable `--help` output |
| Runnable documentation examples | `WikiContract/Fixtures` |
| Component build and packaging instructions | README beside that component |
| Contribution, security, and release process | Repository root policy files |

Where two sources disagree, fix the non-authoritative copy and add a contract check when the fact can be tested.

## Local verification

The required check is deterministic and has no network dependency:

```sh
python3 Scripts/verify_wiki_contract.py
```

After committing edits in a local `Lexicon.wiki` checkout, compare its tagged examples without writing:

```sh
python3 Scripts/refresh_wiki_contract.py --wiki ../Lexicon.wiki
```

To deliberately copy those canonical tagged blocks into the local fixtures and record the wiki commit:

```sh
python3 Scripts/refresh_wiki_contract.py --wiki ../Lexicon.wiki --write
python3 Scripts/verify_wiki_contract.py
```

The write mode requires a clean wiki checkout so the recorded revision always identifies the exact source content.
