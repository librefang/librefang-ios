#!/usr/bin/env python3

import argparse
import json
import sys
from pathlib import Path


def translated(localizations: dict, language: str) -> bool:
    return localizations.get(language, {}).get("stringUnit", {}).get("state") == "translated"


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

    return 1 if has_missing else 0


if __name__ == "__main__":
    sys.exit(main())
