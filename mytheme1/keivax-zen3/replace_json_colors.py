#!/usr/bin/env python3
"""Replace color strings inside a JSON document using a pair-based color mapping.

Supported config formats:
  1. List of objects:
       [{"from": "#RRGGBB", "to": "#RRGGBB"}, ...]
  2. Direct object map:
       {"#RRGGBB": "#RRGGBB", ...}

Rules:
- Only JSON string values that are exactly `#RRGGBB` are replaced.
- Keys are never rewritten.
- Replacements are applied in a single pass over the original JSON so cycles such as
  A<->B do not get broken by sequential re-processing.
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any

HEX_COLOR_RE = re.compile(r"^#[0-9A-Fa-f]{6}$")
MARKDOWN_REPLACEMENT_RE = re.compile(r"^\s*(#[0-9A-Fa-f]{6})\s*:\s*(#[0-9A-Fa-f]{6})\s*$")


def _normalize_color(value: str, field_name: str) -> str:
    if not isinstance(value, str):
        raise ValueError(f"{field_name} must be a string.")
    normalized = value.strip()
    if not HEX_COLOR_RE.fullmatch(normalized):
        raise ValueError(f"{field_name} must be a hex color like '#RRGGBB'.")
    return normalized.lower()


def markdown_to_replacement_pairs(markdown_text: str) -> list[dict[str, str]]:
    """Parse markdown replacement lines like ``#RRGGBB: #RRGGBB``.

    Any line that does not match this exact form is ignored.
    """
    replacements: list[dict[str, str]] = []
    for raw_line in markdown_text.splitlines():
        match = MARKDOWN_REPLACEMENT_RE.fullmatch(raw_line)
        if match is None:
            continue

        from_color = match.group(1).lower()
        to_color = match.group(2).lower()
        if from_color == to_color:
            continue

        replacements.append({"from": from_color, "to": to_color})

    return replacements


def build_replacement_map(raw_pairs: Any) -> dict[str, str]:
    """Convert a config file into a replacement map.

    The mapping is built once and then applied in a single pass to avoid order
    dependence for swap-style rules such as A->B and B->A.
    """
    if isinstance(raw_pairs, dict):
        items = [{"from": source, "to": target} for source, target in raw_pairs.items()]
    elif isinstance(raw_pairs, list):
        items = raw_pairs
    else:
        raise ValueError(
            "replacement config must be a list of {from,to} objects or a dict."
        )

    mapping: dict[str, str] = {}
    for index, item in enumerate(items, start=1):
        if not isinstance(item, dict):
            raise ValueError(f"replacement #{index} must be an object.")
        if "from" not in item or "to" not in item:
            raise ValueError(f"replacement #{index} must contain 'from' and 'to'.")

        source = _normalize_color(item["from"], f"replacement #{index} 'from'")
        target = _normalize_color(item["to"], f"replacement #{index} 'to'")

        if source == target:
            continue

        existing = mapping.get(source)
        if existing is not None and existing != target:
            raise ValueError(
                f"conflicting replacements for '{source}': {existing} and {target}"
            )
        mapping[source] = target

    return mapping


def _transform_json(value: Any, mapping: dict[str, str]) -> Any:
    if isinstance(value, str):
        if HEX_COLOR_RE.fullmatch(value):
            return mapping.get(value.lower(), value)
        return value
    if isinstance(value, list):
        return [_transform_json(item, mapping) for item in value]
    if isinstance(value, dict):
        return {key: _transform_json(item, mapping) for key, item in value.items()}
    return value


def load_replacement_config(path: str | Path) -> dict[str, str]:
    config_path = Path(path)
    text = config_path.read_text(encoding="utf-8-sig")

    if config_path.suffix.lower() in {".md", ".markdown"}:
        payload = markdown_to_replacement_pairs(text)
        return build_replacement_map(payload)

    try:
        payload = json.loads(text)
    except json.JSONDecodeError as exc:
        raise ValueError(f"Could not parse replacement config as JSON: {config_path}") from exc

    if isinstance(payload, dict):
        if "replacements" in payload:
            payload = payload["replacements"]
        elif "pairs" in payload:
            payload = payload["pairs"]

    return build_replacement_map(payload)


def replace_json_colors(
    target_path: str | Path, replacement_path: str | Path
) -> dict[str, Any]:
    target_file = Path(target_path)
    replacement_map = load_replacement_config(replacement_path)

    with target_file.open("r", encoding="utf-8-sig") as fh:
        original = json.load(fh)

    replaced = _transform_json(original, replacement_map)
    return replaced


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Replace exact #RRGGBB values in a JSON document using a color-pair config."
    )
    parser.add_argument(
        "json_file", type=Path, help="Path to the JSON file to rewrite."
    )
    parser.add_argument(
        "replacement_file",
        type=Path,
        help='Path to a JSON or Markdown replacement file. JSON example: [{"from": "#112233", "to": "#445566"}]. Markdown example: "#112233: #445566".',
    )
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        help="Write the converted JSON to this path. Defaults to stdout when omitted.",
    )
    parser.add_argument(
        "--in-place",
        action="store_true",
        help="Overwrite the input JSON file in place.",
    )

    args = parser.parse_args()

    replaced = replace_json_colors(args.json_file, args.replacement_file)

    if args.in_place:
        output_path = args.json_file
    elif args.output is not None:
        output_path = args.output
    else:
        output_path = None

    if output_path is None:
        print(json.dumps(replaced, ensure_ascii=False, indent=4))
        return

    with output_path.open("w", encoding="utf-8") as fh:
        json.dump(replaced, fh, ensure_ascii=False, indent=4)
        fh.write("\n")


if __name__ == "__main__":
    main()
