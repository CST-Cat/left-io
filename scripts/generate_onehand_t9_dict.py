#!/usr/bin/env python3
"""Generate a Rime dictionary from tab-separated word/pinyin rows.

Input format:
    word<TAB>pinyin[ spaces allowed]<TAB>weight optional

When the input file sits next to Rime's essay.txt, the generator uses those
real Rime phrase frequencies for rows without an explicit weight.

Examples:
    你好    ni hao    1000
    输入法  shu ru fa 800

Phrase pronunciations that are not present in the source dictionary can be
provided explicitly with --supplement. This is intentionally preferred over
guessing a phrase from one "primary" reading per character: that guess is
wrong for words such as 银行 and 重庆.
"""

from __future__ import annotations

import argparse
from pathlib import Path
import re
import sys
from dataclasses import dataclass


PINYIN_TO_T9 = {
    "a": "2", "b": "2", "c": "2",
    "d": "3", "e": "3", "f": "3",
    "g": "4", "h": "4", "i": "4",
    "j": "5", "k": "5", "l": "5",
    "m": "6", "n": "6", "o": "6",
    "p": "7", "q": "7", "r": "7", "s": "7",
    "t": "8", "u": "8", "v": "8",
    "w": "9", "x": "9", "y": "9", "z": "9",
}

VALID_PINYIN = re.compile(r"^[a-zA-ZüÜvV:' ]+$")
PERCENT_WEIGHT = re.compile(r"^(\d+(?:\.\d+)?)%$")


@dataclass(frozen=True)
class Entry:
    word: str
    code: str
    weight: int


@dataclass(frozen=True)
class ParsedRows:
    entries: list[Entry]
    unambiguous_character_codes: dict[str, str]


def has_cjk_text(word: str) -> bool:
    for scalar in map(ord, word):
        if (
            scalar == 0x3007
            or 0x3400 <= scalar <= 0x4DBF
            or 0x4E00 <= scalar <= 0x9FFF
            or 0x20000 <= scalar <= 0x2A6DF
            or 0x2A700 <= scalar <= 0x2B73F
            or 0x2B740 <= scalar <= 0x2B81F
            or 0x2B820 <= scalar <= 0x2CEAF
            or 0x2CEB0 <= scalar <= 0x2EBEF
            or 0x30000 <= scalar <= 0x3134F
        ):
            return True
    return False


def normalize_pinyin(raw: str) -> str:
    return (
        raw.strip()
        .lower()
        .replace("u:", "v")
        .replace("ü", "v")
        .replace(" ", "'")
    )


def encode_pinyin(raw: str) -> str | None:
    stripped = raw.strip()
    if stripped.lower() == "xx":
        return None
    if not VALID_PINYIN.match(stripped):
        return None

    normalized = normalize_pinyin(raw)
    code = []
    for char in normalized:
        if char == "'":
            code.append("'")
            continue
        if char not in PINYIN_TO_T9:
            return None
        code.append(PINYIN_TO_T9[char])
    return "".join(code)


def parse_weight(raw: str, word_frequency: int | None) -> int | None:
    stripped = raw.strip()
    if not stripped:
        return word_frequency

    if stripped.isdigit():
        return int(stripped)

    if match := PERCENT_WEIGHT.match(stripped):
        percent = float(match.group(1)) / 100
        if word_frequency is not None:
            return max(1, round(word_frequency * percent))
        return max(1, round(1000 * percent))

    return None


def load_essay_frequencies(path: Path | None) -> dict[str, int]:
    if path is None or not path.exists():
        return {}

    frequencies: dict[str, int] = {}
    with path.open("r", encoding="utf-8") as file:
        for line in file:
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            columns = stripped.split("\t")
            if len(columns) < 2:
                continue
            try:
                frequencies[columns[0].strip()] = int(columns[1].strip())
            except ValueError:
                continue
    return frequencies


def parse_rows(lines: list[str], essay_frequencies: dict[str, int]) -> ParsedRows:
    entries: list[Entry] = []
    character_codes: dict[str, set[str]] = {}
    for line_number, line in enumerate(lines, start=1):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if stripped in {"---", "..."} or ("\t" not in stripped and ":" in stripped):
            continue

        columns = stripped.split("\t")
        if len(columns) < 2:
            print(f"skip line {line_number}: expected word<TAB>pinyin", file=sys.stderr)
            continue

        word = columns[0].strip()
        code = encode_pinyin(columns[1])
        if not word:
            print(f"skip line {line_number}: invalid word or pinyin", file=sys.stderr)
            continue
        if not has_cjk_text(word) or columns[1].strip().lower() == "xx":
            continue
        if code is None:
            print(f"skip line {line_number}: invalid word or pinyin", file=sys.stderr)
            continue

        word_frequency = essay_frequencies.get(word)
        weight = word_frequency if word_frequency is not None else 1
        if len(columns) >= 3:
            parsed_weight = parse_weight(columns[2], word_frequency)
            if parsed_weight is None:
                print(f"skip line {line_number}: invalid weight", file=sys.stderr)
                continue
            weight = parsed_weight

        entries.append(Entry(word=word, code=code, weight=weight))
        if len(word) == 1:
            character_codes.setdefault(word, set()).add(code)

    return ParsedRows(
        entries=entries,
        # Phrase readings cannot be reconstructed safely from a single
        # highest-weight pronunciation of each character. Only derive a phrase
        # when every character has one unambiguous T9 code in the source data.
        unambiguous_character_codes={
            word: next(iter(codes))
            for word, codes in character_codes.items()
            if len(codes) == 1
        }
    )


def derive_essay_phrase_entries(
    essay_frequencies: dict[str, int],
    unambiguous_character_codes: dict[str, str],
    existing_entries: list[Entry]
) -> list[Entry]:
    seen = {(entry.word, entry.code) for entry in existing_entries}
    derived: list[Entry] = []

    for phrase, weight in essay_frequencies.items():
        if len(phrase) < 2 or not has_cjk_text(phrase):
            continue

        codes: list[str] = []
        for character in phrase:
            code = unambiguous_character_codes.get(character)
            if code is None:
                break
            codes.append(code)
        else:
            phrase_code = "'".join(codes)
            key = (phrase, phrase_code)
            if key in seen:
                continue
            seen.add(key)
            derived.append(Entry(word=phrase, code=phrase_code, weight=phrase_weight(weight)))

    return derived


def phrase_weight(frequency: int) -> int:
    return min(2_000_000_000, max(1, frequency) * 1000)


def deduplicated(entries: list[Entry]) -> list[Entry]:
    merged: dict[tuple[str, str], Entry] = {}
    order: list[tuple[str, str]] = []
    for entry in entries:
        key = (entry.word, entry.code)
        previous = merged.get(key)
        if previous is None:
            order.append(key)
            merged[key] = entry
        elif entry.weight > previous.weight:
            merged[key] = entry

    return [merged[key] for key in order]


def emit(entries: list[Entry]) -> None:
    print("# Generated by LeftIO from Rime dictionary data.")
    print("# Production builds use rime-luna-pinyin and rime-essay data.")
    print("# Dictionary data license: LGPL-3.0-only. See THIRD_PARTY_NOTICES.md.")
    print("---")
    print("name: onehand_t9")
    print('version: "0.1.0"')
    print("sort: by_weight")
    print("use_preset_vocabulary: true")
    print("columns:")
    print("  - text")
    print("  - code")
    print("  - weight")
    print("...")
    print()
    for entry in entries:
        print(f"{entry.word}\t{entry.code}\t{entry.weight}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", help="tab-separated word/pinyin/weight file")
    parser.add_argument(
        "--essay",
        help="Rime essay.txt frequency file. Defaults to essay.txt next to input when present."
    )
    parser.add_argument(
        "--no-essay",
        action="store_true",
        help="Do not auto-load a sibling essay.txt frequency file."
    )
    parser.add_argument(
        "--no-essay-phrases",
        action="store_true",
        help="Use essay.txt for weights only; do not derive phrase rows from it."
    )
    parser.add_argument(
        "--supplement",
        action="append",
        default=[],
        help=(
            "Additional word/pinyin/weight rows with explicit phrase readings. "
            "May be supplied more than once."
        )
    )
    args = parser.parse_args()

    input_path = Path(args.input)
    essay_path: Path | None = None
    if args.essay:
        essay_path = Path(args.essay)
    elif not args.no_essay:
        candidate = input_path.parent / "essay.txt"
        if candidate.exists():
            essay_path = candidate

    essay_frequencies = load_essay_frequencies(essay_path)

    with input_path.open("r", encoding="utf-8") as file:
        parsed = parse_rows(file.readlines(), essay_frequencies)

    entries = list(parsed.entries)
    for supplement in args.supplement:
        with Path(supplement).open("r", encoding="utf-8") as file:
            entries += parse_rows(file.readlines(), essay_frequencies).entries
    if essay_frequencies and not args.no_essay_phrases:
        entries += derive_essay_phrase_entries(
            essay_frequencies,
            parsed.unambiguous_character_codes,
            entries
        )
    entries = deduplicated(entries)

    emit(entries)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
