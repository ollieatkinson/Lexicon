#!/usr/bin/env python3
"""Validate Lexicon's deterministic, repository-local wiki contract."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any, Optional
from urllib.parse import unquote, urlsplit


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST = REPOSITORY_ROOT / "Documentation" / "wiki-contract.json"
MARKER_ID = re.compile(r"^[a-z0-9][a-z0-9-]*$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
KNOWN_CHECKS = {
    "cli-validation-contract",
    "composition-precedence",
    "json",
    "runtime-events-api",
    "taskpaper-tabs",
}
MARKDOWN_LINK = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")
MARKDOWN_FENCE = re.compile(r"(?ms)^```[^\n]*\n.*?^```[ \t]*$")


class ContractError(ValueError):
    """A malformed manifest or wiki contract block."""


def normalized_text(text: str) -> str:
    """Normalize line endings and require exactly one trailing newline."""

    return text.replace("\r\n", "\n").replace("\r", "\n").rstrip("\n") + "\n"


def sha256_bytes(content: bytes) -> str:
    return hashlib.sha256(content).hexdigest()


def load_manifest(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ContractError(f"cannot read manifest {path}: {error}") from error
    if not isinstance(value, dict):
        raise ContractError(f"manifest {path} must contain a JSON object")
    return value


def repository_path(relative: str, *, root: Path = REPOSITORY_ROOT) -> Path:
    candidate = Path(relative)
    if candidate.is_absolute():
        raise ContractError(f"repository path must be relative: {relative}")
    resolved_root = root.resolve()
    resolved = (resolved_root / candidate).resolve()
    if resolved != resolved_root and resolved_root not in resolved.parents:
        raise ContractError(f"repository path escapes the checkout: {relative}")
    return resolved


def wiki_page_path(wiki: Path, page: str) -> Path:
    candidate = Path(page)
    if candidate.is_absolute() or candidate.suffix != ".md":
        raise ContractError(f"wiki page must be a relative Markdown file: {page}")
    resolved_wiki = wiki.resolve()
    resolved = (resolved_wiki / candidate).resolve()
    if resolved_wiki not in resolved.parents:
        raise ContractError(f"wiki page escapes the wiki checkout: {page}")
    return resolved


def extract_wiki_block(wiki: Path, contract: dict[str, Any]) -> str:
    page = contract.get("page")
    marker = contract.get("marker")
    language = contract.get("language")
    if not isinstance(page, str) or not isinstance(marker, str) or not isinstance(language, str):
        raise ContractError("contract page, marker, and language must be strings")
    if not MARKER_ID.fullmatch(marker):
        raise ContractError(f"invalid marker ID: {marker!r}")

    path = wiki_page_path(wiki, page)
    try:
        source = normalized_text(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError) as error:
        raise ContractError(f"cannot read wiki page {path}: {error}") from error

    marker_pattern = re.compile(
        rf"(?m)^[ \t]*<!--\s*lexicon-contract:\s*{re.escape(marker)}\s*-->[ \t]*$"
    )
    matches = list(marker_pattern.finditer(source))
    if len(matches) != 1:
        raise ContractError(
            f"{page}: expected one lexicon-contract:{marker} marker, found {len(matches)}"
        )

    remainder = source[matches[0].end() :]
    opening = re.match(r"[ \t]*\n(?:[ \t]*\n)*```([^\n`]*)\n", remainder)
    if opening is None:
        raise ContractError(f"{page}: marker {marker} must be followed by a fenced code block")
    info = opening.group(1).strip().split(maxsplit=1)
    actual_language = info[0] if info else ""
    if actual_language != language:
        raise ContractError(
            f"{page}: marker {marker} expects {language!r}, found {actual_language!r}"
        )

    body_and_rest = remainder[opening.end() :]
    closing = re.search(r"(?m)^```[ \t]*$", body_and_rest)
    if closing is None:
        raise ContractError(f"{page}: marker {marker} has no closing code fence")
    return normalized_text(body_and_rest[: closing.start()])


def check_fixture(contract: dict[str, Any], content: str) -> list[str]:
    errors: list[str] = []
    contract_id = contract.get("id", "<unknown>")
    checks = contract.get("checks", [])
    if not isinstance(checks, list) or not all(isinstance(check, str) for check in checks):
        return [f"{contract_id}: checks must be an array of strings"]

    unknown = sorted(set(checks) - KNOWN_CHECKS)
    if unknown:
        errors.append(f"{contract_id}: unknown checks: {', '.join(unknown)}")

    parsed_json: Any = None
    if "json" in checks:
        try:
            parsed_json = json.loads(content)
        except json.JSONDecodeError as error:
            errors.append(f"{contract_id}: invalid JSON: {error}")

    if "taskpaper-tabs" in checks:
        space_indented = [
            number
            for number, line in enumerate(content.splitlines(), start=1)
            if line.startswith(" ")
        ]
        if space_indented:
            errors.append(
                f"{contract_id}: TaskPaper indentation uses spaces on lines "
                + ", ".join(map(str, space_indented))
            )
        if not any(line.endswith(":") for line in content.splitlines()):
            errors.append(f"{contract_id}: TaskPaper fixture has no node")

    if "composition-precedence" in checks and isinstance(parsed_json, dict):
        expected_order = [
            "composition-base.lexicon",
            "composition-overlay.lexicon",
            "source document",
        ]
        if parsed_json.get("precedence") != expected_order:
            errors.append(f"{contract_id}: precedence must be imports in order, then source")
        if parsed_json.get("path") != "commerce.status" or parsed_json.get("value") != "local":
            errors.append(f"{contract_id}: expected the local commerce.status value to win")

    if "cli-validation-contract" in checks and isinstance(parsed_json, dict):
        commands = parsed_json.get("commands")
        if not isinstance(commands, dict):
            errors.append(f"{contract_id}: commands must be an object")
        else:
            for command in ("validate", "lint"):
                definition = commands.get(command)
                if not isinstance(definition, dict):
                    errors.append(f"{contract_id}: missing {command} contract")
                    continue
                if definition.get("input") != "composed document":
                    errors.append(f"{contract_id}: {command} must validate composed input")
                if definition.get("successExitStatus") != 0:
                    errors.append(f"{contract_id}: {command} success status must be 0")
                if definition.get("invalidExitStatus") != 1:
                    errors.append(f"{contract_id}: {command} invalid status must be 1")
                if definition.get("standardOutput") != "JSON result and document diagnostics":
                    errors.append(f"{contract_id}: {command} document diagnostics must use stdout")
                if definition.get("standardError") != "usage and command execution errors":
                    errors.append(f"{contract_id}: {command} stderr must be reserved for command errors")
        if parsed_json.get("sourceOnlyOption") != "--source-only":
            errors.append(f"{contract_id}: source-only spelling must be --source-only")

    if "runtime-events-api" in checks:
        required = (
            "events.on(",
            "event.matches(I_commerce_ux_type_action.self)",
            "try events.send(",
            "events.finish()",
            "await observer.wait()",
            "observer.cancel()",
        )
        forbidden = (
            "event.matches(commerce.ux.type.action)",
            "events.subscribe",
            "events.then",
            "await events.send",
            ").value",
        )
        for spelling in required:
            if spelling not in content:
                errors.append(f"{contract_id}: missing current Events API spelling {spelling!r}")
        for spelling in forbidden:
            if spelling in content:
                errors.append(f"{contract_id}: contains removed Events API spelling {spelling!r}")

    return errors


def markdown_link_errors(
    files: list[Path],
    *,
    root: Path,
    wiki_style: bool = False,
) -> list[str]:
    errors: list[str] = []
    resolved_root = root.resolve()
    for source in files:
        try:
            text = source.read_text(encoding="utf-8")
        except (OSError, UnicodeError) as error:
            errors.append(f"cannot read Markdown file {source}: {error}")
            continue
        prose = MARKDOWN_FENCE.sub("", text)
        for raw_target in MARKDOWN_LINK.findall(prose):
            raw_target = raw_target.strip()
            if raw_target.startswith("<") and ">" in raw_target:
                target = raw_target[1 : raw_target.index(">")]
            else:
                target = raw_target.split(maxsplit=1)[0]
            target = unquote(target)
            parsed = urlsplit(target)
            if parsed.scheme or parsed.netloc or target.startswith(("#", "/")):
                continue
            relative = parsed.path
            if not relative:
                continue
            resolved = (source.parent / relative).resolve()
            if resolved != resolved_root and resolved_root not in resolved.parents:
                errors.append(f"{source}: relative link escapes its documentation root: {target}")
                continue
            candidates = [resolved]
            if wiki_style and resolved.suffix == "":
                candidates.append(resolved.with_suffix(".md"))
            if not any(candidate.exists() for candidate in candidates):
                errors.append(f"{source}: missing relative link target {target}")
    return errors


def validate_contract(
    manifest_path: Path = DEFAULT_MANIFEST,
    *,
    wiki: Optional[Path] = None,
) -> tuple[list[str], int]:
    errors: list[str] = []
    try:
        manifest = load_manifest(manifest_path)
    except ContractError as error:
        return [str(error)], 0

    if manifest.get("schemaVersion") != 1:
        errors.append("manifest schemaVersion must be 1")

    wiki_metadata = manifest.get("wiki")
    if not isinstance(wiki_metadata, dict):
        errors.append("manifest wiki metadata must be an object")
    else:
        if wiki_metadata.get("canonical") is not True:
            errors.append("wiki.canonical must be true")
        if wiki_metadata.get("repository") != "https://github.com/ollieatkinson/Lexicon.wiki.git":
            errors.append("wiki.repository must name the canonical Lexicon wiki Git repository")
        baseline = wiki_metadata.get("baselineRevision")
        if not isinstance(baseline, str) or not re.fullmatch(r"[0-9a-f]{40}", baseline):
            errors.append("wiki.baselineRevision must be a full Git commit SHA")
        validated = wiki_metadata.get("validatedRevision")
        if validated is not None and (
            not isinstance(validated, str) or not re.fullmatch(r"[0-9a-f]{40}", validated)
        ):
            errors.append("wiki.validatedRevision must be null or a full Git commit SHA")
        if not isinstance(wiki_metadata.get("companionUpdateRequired"), bool):
            errors.append("wiki.companionUpdateRequired must be a boolean")
        if (
            wiki_metadata.get("companionUpdateRequired") is False
            and wiki_metadata.get("validatedRevision") is None
        ):
            errors.append("wiki.validatedRevision is required after the companion update")

    assertions = manifest.get("repositoryAssertions", [])
    if not isinstance(assertions, list):
        errors.append("repositoryAssertions must be an array")
    else:
        for index, assertion in enumerate(assertions):
            if not isinstance(assertion, dict) or not isinstance(assertion.get("file"), str):
                errors.append(f"repositoryAssertions[{index}] must name a file")
                continue
            try:
                assertion_path = repository_path(assertion["file"])
                assertion_text = assertion_path.read_text(encoding="utf-8")
            except (ContractError, OSError, UnicodeError) as error:
                errors.append(f"repositoryAssertions[{index}]: {error}")
                continue
            for expected in assertion.get("contains", []):
                if not isinstance(expected, str) or expected not in assertion_text:
                    errors.append(f"{assertion['file']}: missing required text {expected!r}")
            for forbidden in assertion.get("excludes", []):
                if not isinstance(forbidden, str) or forbidden in assertion_text:
                    errors.append(f"{assertion['file']}: contains forbidden text {forbidden!r}")

    repository_markdown = [
        path
        for path in (
            REPOSITORY_ROOT / "README.md",
            REPOSITORY_ROOT / "CONTRIBUTING.md",
            REPOSITORY_ROOT / "SECURITY.md",
            REPOSITORY_ROOT / "RELEASING.md",
            *sorted((REPOSITORY_ROOT / "Documentation").rglob("*.md")),
        )
        if path.exists()
    ]
    errors.extend(markdown_link_errors(repository_markdown, root=REPOSITORY_ROOT))

    if wiki is not None:
        if not wiki.is_dir():
            errors.append(f"wiki checkout does not exist: {wiki}")
        else:
            errors.extend(
                markdown_link_errors(
                    sorted(wiki.rglob("*.md")),
                    root=wiki,
                    wiki_style=True,
                )
            )

    contracts = manifest.get("contracts")
    if not isinstance(contracts, list):
        return errors + ["manifest contracts must be an array"], 0

    seen_ids: set[str] = set()
    seen_markers: set[tuple[str, str]] = set()
    for index, contract in enumerate(contracts):
        if not isinstance(contract, dict):
            errors.append(f"contracts[{index}] must be an object")
            continue

        contract_id = contract.get("id")
        marker = contract.get("marker")
        page = contract.get("page")
        language = contract.get("language")
        fixture = contract.get("fixture")
        expected_hash = contract.get("sha256")
        if not isinstance(contract_id, str) or not MARKER_ID.fullmatch(contract_id):
            errors.append(f"contracts[{index}] has invalid id {contract_id!r}")
            continue
        if contract_id in seen_ids:
            errors.append(f"duplicate contract id: {contract_id}")
        seen_ids.add(contract_id)
        if not isinstance(marker, str) or not MARKER_ID.fullmatch(marker):
            errors.append(f"{contract_id}: invalid marker {marker!r}")
        if not isinstance(page, str):
            errors.append(f"{contract_id}: page must be a string")
        elif Path(page).is_absolute() or Path(page).suffix != ".md" or ".." in Path(page).parts:
            errors.append(f"{contract_id}: page must be a safe relative Markdown path")
        elif isinstance(marker, str):
            source_key = (page, marker)
            if source_key in seen_markers:
                errors.append(f"{contract_id}: duplicate marker {marker} in {page}")
            seen_markers.add(source_key)
        if not isinstance(language, str) or not language:
            errors.append(f"{contract_id}: language must be a non-empty string")
        if not isinstance(fixture, str):
            errors.append(f"{contract_id}: fixture must be a string")
            continue
        if not isinstance(expected_hash, str) or not SHA256.fullmatch(expected_hash):
            errors.append(f"{contract_id}: sha256 must be 64 lowercase hexadecimal characters")

        try:
            fixture_path = repository_path(fixture)
            content_bytes = fixture_path.read_bytes()
            content = content_bytes.decode("utf-8")
        except (ContractError, OSError, UnicodeError) as error:
            errors.append(f"{contract_id}: cannot read fixture: {error}")
            continue

        actual_hash = sha256_bytes(content_bytes)
        if actual_hash != expected_hash:
            errors.append(
                f"{contract_id}: fixture SHA mismatch; expected {expected_hash}, found {actual_hash}"
            )
        if not content.endswith("\n"):
            errors.append(f"{contract_id}: fixture must end with a newline")
        if "\r" in content:
            errors.append(f"{contract_id}: fixture must use LF line endings")
        errors.extend(check_fixture(contract, content))

        if wiki is not None:
            try:
                wiki_content = extract_wiki_block(wiki, contract)
            except ContractError as error:
                errors.append(f"{contract_id}: {error}")
            else:
                if normalized_text(content) != wiki_content:
                    errors.append(
                        f"{contract_id}: fixture differs from marker {marker} in {page}"
                    )

    return errors, len(contracts)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate repository-local wiki fixtures and, optionally, a wiki checkout."
    )
    parser.add_argument(
        "--manifest",
        type=Path,
        default=DEFAULT_MANIFEST,
        help="wiki contract manifest (default: Documentation/wiki-contract.json)",
    )
    parser.add_argument(
        "--wiki",
        type=Path,
        help="optional local Lexicon.wiki checkout containing tagged contract blocks",
    )
    args = parser.parse_args()

    errors, count = validate_contract(args.manifest.resolve(), wiki=args.wiki)
    if errors:
        for error in errors:
            print(f"wiki-contract: error: {error}", file=sys.stderr)
        return 1

    scope = "local fixtures" if args.wiki is None else f"local fixtures and {args.wiki}"
    print(f"wiki-contract: verified {count} contracts against {scope}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
