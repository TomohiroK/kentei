#!/usr/bin/env python3
"""基準回答の提出文を Swift の定義から取り出し、測定用の JSON を書き出す。

提出文を2箇所に持つと必ずずれる。Swift 側を唯一の出所とする。

    python3 server/scripts/extract-golden.py
"""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "Kentei/Domain/DemoAssessment.swift"
DESTINATION = ROOT / "server/scripts/golden-candidates.json"

# golden(...) / goldenA(...) の両方を拾う。設問は級ごとの定数から解決する。
PATTERN = re.compile(
    r'(goldenA?)\(\s*id:\s*"([^"]+)",\s*text:\s*"((?:[^"\\]|\\.)*)"', re.S
)
PROMPT_PATTERN = re.compile(r'static let writingPrompt([AB]) = "((?:[^"\\]|\\.)*)"')
RUBRIC_BY_HELPER = {"golden": "rubric-writing-b", "goldenA": "rubric-writing-a"}


def unescape(raw: str) -> str:
    return raw.replace("\\n", "\n").replace('\\"', '"').replace("\\\\", "\\")


def main() -> None:
    swift = SOURCE.read_text(encoding="utf-8")
    prompts = {level: unescape(raw) for level, raw in PROMPT_PATTERN.findall(swift)}
    if not prompts:
        raise SystemExit(f"{SOURCE} から設問を取り出せませんでした")

    items = [
        {
            "id": identifier,
            "rubricId": RUBRIC_BY_HELPER[helper],
            "prompt": prompts["A" if helper == "goldenA" else "B"],
            "text": unescape(raw),
        }
        for helper, identifier, raw in PATTERN.findall(swift)
    ]
    if not items:
        raise SystemExit(f"{SOURCE} から基準回答を取り出せませんでした")
    DESTINATION.write_text(
        json.dumps(items, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"{len(items)} 件を {DESTINATION.relative_to(ROOT)} に書き出しました")


if __name__ == "__main__":
    main()
