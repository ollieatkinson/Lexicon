#!/usr/bin/env python3
"""Check imported-only edits against the real incremental SwiftPM build graph."""
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
package = root / "IntegrationTests/Plugins"
fixtures = [
    ("LibraryPluginFixture", "North", "north", "import SwiftLexicon\n"),
    ("StandalonePluginFixture", "Nested", "standalone", ""),
]

for target, folder, name, imports in fixtures:
    source = package / "Sources" / target / f"{target}.swift"
    fragment = source.parent / folder / "Parts/fields.taskpaper"
    command = ["swift", "build", "--package-path", str(package), "--target", target]
    subprocess.run(command, cwd=root, check=True)
    original_source, original_fragment = source.read_bytes(), fragment.read_bytes()
    try:
        # Keep the entrypoint unchanged. Its imported file is the generation
        # dependency; the consumer edit makes stale generated Swift fail to compile.
        fragment.write_bytes(original_fragment + b"\tincremental:\n")
        source.write_text(original_source.decode() + imports +
            f"\npublic func check_incremental_import() {{ _ = {name}.incremental }}\n")
        subprocess.run(command, cwd=root, check=True)
    finally:
        source.write_bytes(original_source)
        fragment.write_bytes(original_fragment)
    # Also regenerate after removing the imported declaration.
    subprocess.run(command, cwd=root, check=True)
