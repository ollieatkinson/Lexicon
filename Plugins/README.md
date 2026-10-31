# Swift build plugins

Both build plugins discover regular files recursively beneath the target
directory. Generation entrypoints have the final, case-sensitive extension
`.lexicon`. Local `.taskpaper` files are dependency inputs for composition, but
do not generate independent Swift files. Names such as `catalog.notlexicon` are
ignored. Inputs are sorted by target-relative paths before commands are created.

Use `.taskpaper` for imported fragments when only the composed root should be
generated. Both plugins regenerate after changes to those fragments, including
nested imports beneath the target directory. For example:

```text
catalog.lexicon -> imports Parts/fields.taskpaper
```

This produces `catalog.swift` with the composed fields and no second Swift root
for the fragment. Keep local imports beneath the target directory for automatic
dependency tracking; remote/outside-target imports are not discovered by this
directory scan. Exclude fragment directories from SwiftPM source discovery when
they are build-time only, or copy them as resources when runtime composition
needs them.

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
input may compose another local `.lexicon` or `.taskpaper`; changing one therefore
regenerates every potentially affected output.

`SwiftStandAloneGeneratorPlugin` accepts zero or one generation entrypoint per target because
every standalone output contains the runtime declarations. Targets with multiple
standalone inputs fail with guidance to split the inputs into separate targets
or precompose them into one self-contained `.lexicon` before the plugin runs.
A same-target `.lexicon` import is a second generation entrypoint. Use imported
`.taskpaper` fragments to compose one standalone output within the target.

`python3 Scripts/check_plugin_imports.py` checks actual incremental builds for
both plugins: an imported-only edit introduces a new generated field, a consumer
must compile against it, and removing the field triggers regeneration again.
