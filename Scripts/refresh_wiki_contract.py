#!/usr/bin/env python3
"""Refresh local contract fixtures from explicitly tagged wiki blocks."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Any

from verify_wiki_contract import (
    DEFAULT_MANIFEST,
    ContractError,
    check_fixture,
    extract_wiki_block,
    load_manifest,
    repository_path,
    sha256_bytes,
    validate_contract,
)


def git_output(wiki: Path, *arguments: str) -> str:
    try:
        result = subprocess.run(
            ["git", "-C", str(wiki), *arguments],
            check=True,
            capture_output=True,
            text=True,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        raise ContractError(f"cannot inspect wiki Git checkout: {error}") from error
    return result.stdout.strip()


def staged_refresh(
    manifest: dict[str, Any],
    wiki: Path,
) -> tuple[list[tuple[Path, bytes, dict[str, Any]]], str]:
    if not wiki.is_dir():
        raise ContractError(f"wiki checkout does not exist: {wiki}")
    if git_output(wiki, "status", "--porcelain"):
        raise ContractError("wiki checkout must be clean before recording its revision")
    revision = git_output(wiki, "rev-parse", "HEAD")
    if len(revision) != 40:
        raise ContractError(f"unexpected wiki revision: {revision!r}")

    staged: list[tuple[Path, bytes, dict[str, Any]]] = []
    contracts = manifest.get("contracts")
    if not isinstance(contracts, list):
        raise ContractError("manifest contracts must be an array")
    for contract in contracts:
        if not isinstance(contract, dict) or not isinstance(contract.get("fixture"), str):
            raise ContractError("every contract must be an object with a fixture")
        text = extract_wiki_block(wiki, contract)
        fixture_errors = check_fixture(contract, text)
        if fixture_errors:
            raise ContractError("; ".join(fixture_errors))
        content = text.encode("utf-8")
        path = repository_path(contract["fixture"])
        staged.append((path, content, contract))
    return staged, revision


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Check a tagged wiki checkout against local fixtures. "
            "Pass --write to refresh fixtures and the recorded wiki revision."
        )
    )
    parser.add_argument("--wiki", type=Path, required=True, help="local Lexicon.wiki checkout")
    parser.add_argument(
        "--manifest",
        type=Path,
        default=DEFAULT_MANIFEST,
        help="wiki contract manifest (default: Documentation/wiki-contract.json)",
    )
    parser.add_argument(
        "--write",
        action="store_true",
        help="copy tagged wiki blocks into local fixtures; the default is read-only",
    )
    args = parser.parse_args()
    manifest_path = args.manifest.resolve()
    wiki = args.wiki.resolve()

    if not args.write:
        errors, count = validate_contract(manifest_path, wiki=wiki)
        if errors:
            for error in errors:
                print(f"wiki-contract: error: {error}", file=sys.stderr)
            return 1
        print(f"wiki-contract: {count} wiki blocks match their local fixtures")
        return 0

    try:
        manifest = load_manifest(manifest_path)
        local_errors, _ = validate_contract(manifest_path)
        if local_errors:
            raise ContractError("; ".join(local_errors))
        staged, revision = staged_refresh(manifest, wiki)
    except ContractError as error:
        print(f"wiki-contract: error: {error}", file=sys.stderr)
        return 1

    wiki_metadata = manifest.get("wiki")
    if not isinstance(wiki_metadata, dict):
        print("wiki-contract: error: manifest wiki metadata must be an object", file=sys.stderr)
        return 1
    wiki_metadata["validatedRevision"] = revision
    wiki_metadata["companionUpdateRequired"] = False

    for path, content, contract in staged:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
        contract["sha256"] = sha256_bytes(content)

    manifest_path.write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )

    errors, count = validate_contract(manifest_path, wiki=wiki)
    if errors:
        for error in errors:
            print(f"wiki-contract: error after refresh: {error}", file=sys.stderr)
        return 1
    print(f"wiki-contract: refreshed {count} contracts from wiki revision {revision}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
