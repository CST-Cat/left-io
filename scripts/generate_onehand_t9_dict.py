#!/usr/bin/env python3
"""Generate a Rime dictionary from tab-separated word/pinyin rows.

Input format:
    word<TAB>pinyin[ spaces allowed]<TAB>weight optional

Examples:
    你好    ni hao    1000
    输入法  shu ru fa 800
"""

from __future__ import annotations

import argparse
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

VALID_PINYIN = re.compile(r"^[a-zA-ZüÜvV: ]+$")


@dataclass(frozen=True)
class Entry:
    word: str
    code: str
    weight: int


def normalize_pinyin(raw: str) -> str:
    return (
        raw.strip()
        .lower()
        .replace("u:", "v")
        .replace("ü", "v")
        .replace(" ", "'")
    )


def encode_pinyin(raw: str) -> str | None:
    if not VALID_PINYIN.match(raw.strip()):
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


def parse_rows(lines: list[str]) -> list[Entry]:
    entries: list[Entry] = []
    for line_number, line in enumerate(lines, start=1):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue

        columns = stripped.split("\t")
        if len(columns) < 2:
            print(f"skip line {line_number}: expected word<TAB>pinyin", file=sys.stderr)
            continue

        word = columns[0].strip()
        code = encode_pinyin(columns[1])
        if not word or code is None:
            print(f"skip line {line_number}: invalid word or pinyin", file=sys.stderr)
            continue

        weight = 100
        if len(columns) >= 3 and columns[2].strip():
            try:
                weight = int(columns[2])
            except ValueError:
                print(f"skip line {line_number}: invalid weight", file=sys.stderr)
                continue

        entries.append(Entry(word=word, code=code, weight=weight))
    return entries


def emit(entries: list[Entry]) -> None:
    print("---")
    print("name: onehand_t9")
    print('version: "0.1.0"')
    print("sort: by_weight")
    print("use_preset_vocabulary: true")
    print("...")
    print()
    for entry in entries:
        print(f"{entry.word}\t{entry.code}\t{entry.weight}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", help="tab-separated word/pinyin/weight file")
    args = parser.parse_args()

    with open(args.input, "r", encoding="utf-8") as file:
        entries = parse_rows(file.readlines())

    emit(entries)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
