#!/usr/bin/env python3

import argparse
import json
import re
import sys
from pathlib import Path


def translated(localizations: dict, language: str) -> bool:
    return localizations.get(language, {}).get("stringUnit", {}).get("state") == "translated"


SUSPICIOUS_LABEL_PATTERN = re.compile(
    r"var\s+(label|title|friendlyAction|localized[A-Z]\w*)\s*:\s*String\s*\{(?P<body>.*?)\n\}",
    re.S,
)
RAW_STRING_RETURN_PATTERN = re.compile(r'return\s+"[^"]+"')


def suspicious_swift_properties(root: Path) -> list[tuple[Path, str]]:
    findings: list[tuple[Path, str]] = []

    for path in root.rglob("*.swift"):
        body = path.read_text()
        for match in SUSPICIOUS_LABEL_PATTERN.finditer(body):
            snippet = match.group("body")
            if "String(localized:" in snippet:
                continue
            if "replacingOccurrences" in snippet or ".capitalized" in snippet or "splitCamelCase" in snippet:
                continue
            if RAW_STRING_RETURN_PATTERN.search(snippet):
                findings.append((path, match.group(0).strip()))

    return findings


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
    args = parser.parse_args()

    catalog_path = Path(args.catalog)
    payload = json.loads(catalog_path.read_text())
    strings = payload.get("strings", {})

    missing: dict[str, list[str]] = {language: [] for language in args.languages}

    for key, entry in strings.items():
        localizations = entry.get("localizations", {})
        if "en" not in localizations:
            continue

        for language in args.languages:
            if not translated(localizations, language):
                missing[language].append(key)

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

    has_suspicious_swift = False
    if args.scan_swift:
        findings = suspicious_swift_properties(Path(args.swift_root))
        if findings:
            has_suspicious_swift = True
            print("swift-scan: suspicious raw-English label/title properties found")
            for path, snippet in findings:
                print(f"  - {path}")
                print(f"    {snippet.splitlines()[0]}")
        else:
            print("swift-scan: OK")

    return 1 if has_missing or has_suspicious_swift else 0


if __name__ == "__main__":
    sys.exit(main())
