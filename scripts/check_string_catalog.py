#!/usr/bin/env python3

import argparse
import ast
import json
import re
import sys
from pathlib import Path


SAME_AS_SOURCE_ALLOWLIST = {
    "LibreFang",
    "MCP",
    "OFP",
    "OFP Network",
    "Webhook",
    "URL",
    "JSON",
    "API",
    "JWT",
    "OAuth",
    "mTLS",
    "Email",
    "SMS",
    "Push",
    "A2A Agents",
    "SOUL.md",
    "IDENTITY.md",
    "AGENTS.md",
    "MEMORY.md",
    "state.current_task",
    "true",
    "false",
    "null",
}
SAME_AS_SOURCE_PLACEHOLDER_PATTERN = re.compile(r".*%[-0-9$.@ldf]+.*")


def has_translated_content(node: object) -> bool:
    if isinstance(node, dict):
        string_unit = node.get("stringUnit")
        if isinstance(string_unit, dict) and string_unit.get("state") == "translated":
            return True
        return any(has_translated_content(value) for value in node.values())
    if isinstance(node, list):
        return any(has_translated_content(value) for value in node)
    return False


def requires_translation(key: str, entry: dict) -> bool:
    return bool(key) and entry.get("extractionState") != "stale"


def translated_value(localizations: dict, language: str) -> str | None:
    string_unit = (localizations.get(language, {}) or {}).get("stringUnit", {})
    value = string_unit.get("value")
    return value if isinstance(value, str) and value else None


def same_as_source_candidate(key: str, translated: str) -> bool:
    if translated != key:
        return False
    if key in SAME_AS_SOURCE_ALLOWLIST:
        return False
    if SAME_AS_SOURCE_PLACEHOLDER_PATTERN.fullmatch(key):
        return False
    if "\\(" in key:
        return False
    if any(token in key for token in ("ByteCountFormatter", "RelativeDateTimeFormatter", "String(localized:")):
        return False
    if re.fullmatch(r"[0-9A-Za-z .:/_-]+", key) and not re.search(r"[A-Za-z]{3,}", key):
        return False
    return True


SUSPICIOUS_LABEL_PATTERN = re.compile(
    r"var\s+(label|title|friendlyAction|localized[A-Z]\w*)\s*:\s*String\s*\{(?P<body>.*?)\n\}",
    re.S,
)
RAW_STRING_RETURN_PATTERN = re.compile(r'return\s+"[^"]+"')
STRING_FORMAT_PATTERN = re.compile(r"String\(format:\s*")
RAW_CURRENCY_PATTERN = re.compile(
    r'return\s+"\$[^"]*"|"\$\\\([^"]+|Text\("\$[^"]*"|Label\("\$[^"]*"|<\$[0-9]',
)
DISPLAY_CASE_TRANSFORM_PATTERN = re.compile(
    r"Text\([^)\n]*\.(capitalized|uppercased)\b|Label\([^)\n]*\.(capitalized|uppercased)\b",
)
STRING_LOCALIZED_PREFIX = "String(localized:"
LOCALIZATION_LITERAL_PREFIXES = (
    STRING_LOCALIZED_PREFIX,
    "Text(",
    "Label(",
    "Button(",
    "Section(",
    ".navigationTitle(",
    "TextField(",
    "LocalizedStringResource(",
    "Menu(",
    "Picker(",
    "Toggle(",
    ".alert(",
    "confirmationDialog(",
    "ProgressView(",
    "ContentUnavailableView(",
    "LabeledContent(",
)
SOURCE_LITERAL_ALLOWLIST = {
    "OK",
    "URL",
    "JSON",
    "MCP",
    "LibreFang",
    "Unknown",
    "Webhook",
    "JWT",
    "OAuth",
    "mTLS",
    "Email",
    "SMS",
    "Push",
    "A2A Agents",
    "SOUL.md",
    "IDENTITY.md",
    "AGENTS.md",
    "MEMORY.md",
    "state.current_task",
    "true",
    "false",
    "null",
}
CATALOG_PLACEHOLDER_PATTERN = re.compile(r"%(?:\d+\$)?[-+#0 ]*(?:\d+)?(?:\.\d+)?(?:ll)?[@dDuUxXoOfFeEgGcCsSpaA]")


def collapse_raw_interpolations(value: str) -> str:
    buffer: list[str] = []
    i = 0

    while i < len(value):
        ch = value[i]

        if ch == "\\" and i + 1 < len(value):
            nxt = value[i + 1]

            if nxt == "(":
                buffer.append("<?>")
                i += 2
                depth = 1

                while i < len(value) and depth > 0:
                    inner = value[i]

                    if inner == '"':
                        i += 1
                        while i < len(value):
                            if value[i] == "\\" and i + 1 < len(value):
                                i += 2
                                continue
                            if value[i] == '"':
                                i += 1
                                break
                            i += 1
                        continue

                    if inner == "(":
                        depth += 1
                    elif inner == ")":
                        depth -= 1
                    i += 1

                continue

            if nxt == '"':
                buffer.append('"')
                i += 2
                continue

        buffer.append(ch)
        i += 1

    return "".join(buffer)


def suspicious_swift_properties(root: Path) -> list[tuple[Path, str, str]]:
    findings: list[tuple[Path, str, str]] = []

    for path in root.rglob("*.swift"):
        body = path.read_text()
        for match in SUSPICIOUS_LABEL_PATTERN.finditer(body):
            snippet = match.group("body")
            if "String(localized:" in snippet:
                continue
            if "replacingOccurrences" in snippet or ".capitalized" in snippet or "splitCamelCase" in snippet:
                continue
            if RAW_STRING_RETURN_PATTERN.search(snippet):
                findings.append((path, "raw-property", match.group(0).strip()))

        for line_no, line in enumerate(body.splitlines(), start=1):
            if STRING_FORMAT_PATTERN.search(line):
                findings.append((path, f"string-format:{line_no}", line.strip()))
            elif RAW_CURRENCY_PATTERN.search(line):
                findings.append((path, f"raw-currency:{line_no}", line.strip()))
            elif DISPLAY_CASE_TRANSFORM_PATTERN.search(line):
                findings.append((path, f"display-case-transform:{line_no}", line.strip()))

    return findings


def decode_source_literal(raw: str) -> str:
    if "\\(" in raw:
        return raw
    try:
        return ast.literal_eval(f'"{raw}"')
    except (SyntaxError, ValueError):
        return raw


def normalize_mojibake(value: str) -> str:
    return value.replace("Â·", "·").replace("â†’", "→").replace("â¦", "…")


def parse_swift_string(text: str, start: int) -> tuple[str, int] | None:
    if start >= len(text) or text[start] != '"':
        return None

    i = start + 1
    buffer: list[str] = []

    while i < len(text):
        ch = text[i]
        if ch == '"':
            return "".join(buffer), i + 1
        if ch == "\\":
            if i + 1 >= len(text):
                buffer.append(ch)
                i += 1
                continue

            nxt = text[i + 1]
            if nxt == "(":
                buffer.append("<?>")
                i += 2
                depth = 1
                while i < len(text) and depth > 0:
                    if text[i] == '"':
                        parsed = parse_swift_string(text, i)
                        if parsed is None:
                            break
                        _, i = parsed
                        continue
                    if text[i] == "(":
                        depth += 1
                    elif text[i] == ")":
                        depth -= 1
                    i += 1
                continue

            buffer.append(ch)
            buffer.append(nxt)
            i += 2
            continue

        buffer.append(ch)
        i += 1

    return None


def localized_literal_entries(root: Path) -> list[tuple[Path, str]]:
    findings: list[tuple[Path, str]] = []

    for path in root.rglob("*.swift"):
        body = path.read_text()
        for prefix in LOCALIZATION_LITERAL_PREFIXES:
            offset = 0
            while True:
                start = body.find(prefix, offset)
                if start == -1:
                    break

                if prefix[0].isalpha() and start > 0 and (body[start - 1].isalnum() or body[start - 1] == "_"):
                    offset = start + 1
                    continue

                cursor = start + len(prefix)
                while cursor < len(body) and body[cursor].isspace():
                    cursor += 1

                parsed = parse_swift_string(body, cursor)
                if parsed is None:
                    offset = cursor
                    continue

                literal, end = parsed
                findings.append((path, normalize_mojibake(literal)))
                offset = end

    return findings


def localized_string_literals(root: Path) -> list[tuple[Path, str]]:
    return localized_literal_entries(root)


def dynamic_literal_skeleton(value: str) -> str:
    value = normalize_mojibake(value)
    value = value.replace("<?>", "§§INTERP§§")
    value = collapse_raw_interpolations(value)
    value = CATALOG_PLACEHOLDER_PATTERN.sub("<?>", value)
    value = value.replace("§§INTERP§§", "<?>")
    value = value.replace("%%", "%")
    return re.sub(r"\s+", " ", value).strip()


def missing_simple_source_literals(root: Path, catalog_strings: dict) -> list[tuple[Path, str]]:
    findings: list[tuple[Path, str]] = []

    for path, raw_key in localized_literal_entries(root):
        if "<?>" in raw_key or "\\(" in raw_key:
            continue

        key = decode_source_literal(raw_key)
        if key in SOURCE_LITERAL_ALLOWLIST:
            continue
        if not any(ch.isalpha() for ch in key):
            continue
        if key in catalog_strings:
            continue
        findings.append((path, key))

    deduped: dict[tuple[str, str], tuple[Path, str]] = {}
    for path, key in findings:
        deduped.setdefault((str(path), key), (path, key))
    return sorted(deduped.values(), key=lambda item: (str(item[0]), item[1]))


def missing_dynamic_localized_literals(root: Path, catalog_strings: dict) -> list[tuple[Path, str]]:
    catalog_skeletons = {dynamic_literal_skeleton(key) for key in catalog_strings}
    findings: list[tuple[Path, str]] = []

    for path, key in localized_string_literals(root):
        if "\\(" not in key and "<?>" not in key:
            continue
        skeleton = dynamic_literal_skeleton(key)
        if skeleton in catalog_skeletons:
            continue
        findings.append((path, key))

    deduped: dict[tuple[str, str], tuple[Path, str]] = {}
    for path, key in findings:
        deduped.setdefault((str(path), key), (path, key))
    return sorted(deduped.values(), key=lambda item: (str(item[0]), item[1]))


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Check that required localizations exist for every string catalog entry with English text."
    )
    parser.add_argument(
        "catalog",
        nargs="?",
        default="librefang-ios/Localizable.xcstrings",
        help="Path to the .xcstrings file.",
    )
    parser.add_argument(
        "--language",
        action="append",
        default=["zh-Hans"],
        dest="languages",
        help="Localization identifier that must exist. Repeat for multiple languages.",
    )
    parser.add_argument(
        "--swift-root",
        default="librefang-ios",
        help="Root folder for optional Swift localization scans.",
    )
    parser.add_argument(
        "--scan-swift",
        action="store_true",
        help="Also scan Swift files for obvious raw-English label/title properties.",
    )
    parser.add_argument(
        "--scan-source-literals",
        action="store_true",
        help="Also scan Swift source for simple localized literals that are missing from the string catalog.",
    )
    parser.add_argument(
        "--scan-dynamic-literals",
        action="store_true",
        help="Also scan interpolated String(localized:) literals for missing string catalog entries.",
    )
    parser.add_argument(
        "--summary",
        action="store_true",
        help="Print translation coverage totals for each requested language.",
    )
    args = parser.parse_args()

    catalog_path = Path(args.catalog)
    payload = json.loads(catalog_path.read_text())
    strings = payload.get("strings", {})

    missing: dict[str, list[str]] = {language: [] for language in args.languages}
    same_as_source: dict[str, list[str]] = {language: [] for language in args.languages}
    source_backed_key_count = 0

    for key, entry in strings.items():
        if not requires_translation(key, entry):
            continue
        source_backed_key_count += 1

        localizations = entry.get("localizations", {})

        for language in args.languages:
            localization = localizations.get(language, {})
            if not has_translated_content(localization):
                missing[language].append(key)
                continue

            translated = translated_value(localizations, language)
            if translated and same_as_source_candidate(key, translated):
                same_as_source[language].append(key)

    if args.summary:
        print(f"source-backed keys: {source_backed_key_count}")
        for language in args.languages:
            translated_count = source_backed_key_count - len(missing[language])
            print(
                f"{language}: translated {translated_count}/{source_backed_key_count}, missing {len(missing[language])}"
            )
            print(f"{language}: same-as-source candidates {len(same_as_source[language])}")

    has_missing = False
    for language in args.languages:
        missing_keys = missing[language]
        if not missing_keys:
            print(f"{language}: OK")
            continue

        has_missing = True
        print(f"{language}: missing {len(missing_keys)} keys")
        for key in missing_keys:
            print(f"  - {key}")

    has_same_as_source = False
    for language in args.languages:
        same_as_source_keys = same_as_source[language]
        if not same_as_source_keys:
            print(f"{language}: no suspicious same-as-source values")
            continue

        has_same_as_source = True
        print(f"{language}: suspicious same-as-source values {len(same_as_source_keys)}")
        for key in same_as_source_keys:
            print(f"  - {key}")

    has_suspicious_swift = False
    if args.scan_swift:
        findings = suspicious_swift_properties(Path(args.swift_root))
        if findings:
            has_suspicious_swift = True
            print("swift-scan: suspicious raw-English label/title properties found")
            for path, kind, snippet in findings:
                print(f"  - {path} [{kind}]")
                print(f"    {snippet.splitlines()[0]}")
        else:
            print("swift-scan: OK")

    has_missing_source_literals = False
    if args.scan_source_literals:
        findings = missing_simple_source_literals(Path(args.swift_root), strings)
        if findings:
            has_missing_source_literals = True
            print("source-literal-scan: missing simple catalog entries")
            for path, key in findings:
                print(f"  - {path}: {key}")
        else:
            print("source-literal-scan: OK")

    has_missing_dynamic_literals = False
    if args.scan_dynamic_literals:
        findings = missing_dynamic_localized_literals(Path(args.swift_root), strings)
        if findings:
            has_missing_dynamic_literals = True
            print("dynamic-literal-scan: missing interpolated catalog entries")
            for path, key in findings:
                print(f"  - {path}: {key}")
        else:
            print("dynamic-literal-scan: OK")

    return (
        1
        if has_missing
        or has_same_as_source
        or has_suspicious_swift
        or has_missing_source_literals
        or has_missing_dynamic_literals
        else 0
    )


if __name__ == "__main__":
    sys.exit(main())
