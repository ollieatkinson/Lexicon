# Swift build plugins

Both build plugins discover regular files recursively beneath the target
directory. An input is recognized only when its final, case-sensitive extension
is exactly `.lexicon`; names such as `catalog.notlexicon` are ignored. Inputs are
sorted by their normalized target-relative paths before commands are created.

Generated files live below the plugin work directory's `GeneratedSources`
folder. A root input keeps its stem:

```text
catalog.lexicon -> GeneratedSources/catalog.swift
```

A nested input keeps its relative directory and prefixes its generated basename
with that directory:

```text
North/catalog.lexicon -> GeneratedSources/North/North__catalog.swift
Admin/UI/catalog.lexicon -> GeneratedSources/Admin/UI/Admin__UI__catalog.swift
```

The basename prefix is required because Swift otherwise compiles same-named
sources from different directories to the same object filename. Both plugins
validate the complete, case-folded and Unicode-normalized output map and the
generated source basenames before returning commands. They fail with the two
conflicting inputs if either generated paths or Swift object filenames would
collide.

`SwiftLibraryGeneratorPlugin` accepts zero or more inputs. Each generation
command declares the complete discovered input set as dependencies because an
input may compose another local `.lexicon`; changing an imported file therefore
regenerates every potentially affected output.

`SwiftStandAloneGeneratorPlugin` accepts zero or one input per target because
every standalone output contains the runtime declarations. Targets with multiple
standalone inputs fail with guidance to split the inputs into separate targets
or precompose them into one self-contained `.lexicon` before the plugin runs.
A same-target `.lexicon` import would itself be discovered as a second input, so
the standalone plugin does not support that arrangement.
