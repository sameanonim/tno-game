#!/usr/bin/env python3
"""
Clausewitz Data Pipeline for TNO Turn-Based Game in Godot 4
----------------------------------------------------------
Parses Clausewitz syntax (.txt from HoI4 / TNO mod) and localization (.yml)
into structured JSON databases for events, focus trees (directives), and states.

Usage:
  python clausewitz_parser.py --input-dir raw_tno_data/ --output-dir data/
"""

import argparse
import json
import os
import re
import sys
from typing import Any, Dict, List, Union


class ClausewitzTokenizer:
    """Tokenizes Clausewitz script files into tokens, supporting comparison operators."""
    TOKEN_RE = re.compile(
        r'("(?:\\.|[^"\\])*")|(#.*?$)|([{}])|(>=|<=|!=|>|<|=)|([^\s#{}"=><!]+)',
        re.MULTILINE
    )

    @classmethod
    def tokenize(cls, text: str) -> List[str]:
        tokens: List[str] = []
        for match in cls.TOKEN_RE.finditer(text):
            string_lit, comment, brace, op, word = match.groups()
            if comment:
                continue
            if string_lit is not None:
                cleaned = string_lit[1:-1].replace('\\"', '"').replace('\\\\', '\\')
                tokens.append(cleaned)
            elif brace:
                tokens.append(brace)
            elif op:
                tokens.append(op)
            elif word:
                tokens.append(word)
        return tokens


class ClausewitzParser:
    """Recursive descent parser for Clausewitz AST with relational operator AST generation."""
    RELATIONAL_OPS = {">=", "<=", "!=", ">", "<", "="}

    def __init__(self, tokens: List[str]):
        self.tokens: List[str] = tokens
        self.pos: int = 0
        self.length: int = len(tokens)

    def parse(self) -> Dict[str, Any]:
        result: Dict[str, Any] = {}
        while self.pos < self.length:
            if self.peek() == "}":
                break
            key = self.consume()
            if key is None:
                break

            op = self.peek()
            if op in self.RELATIONAL_OPS:
                self.consume()  # eat operator
                val = self.parse_value()

                entry = {"operator": op, "value": val} if op != "=" else val

                if key in result:
                    if not isinstance(result[key], list):
                        result[key] = [result[key]]
                    result[key].append(entry)
                else:
                    result[key] = entry
            else:
                # Standalone word or list entry
                if "list_values" not in result:
                    result["list_values"] = []
                result["list_values"].append(key)
        return result

    def parse_value(self) -> Any:
        token = self.peek()
        if token == "{":
            self.consume()  # eat '{'
            nested_dict: Dict[str, Any] = {}
            nested_list: List[Any] = []
            is_pure_list = False

            while self.pos < self.length and self.peek() != "}":
                curr = self.peek()
                next_tok = self.peek_ahead(1)
                if next_tok in self.RELATIONAL_OPS:
                    k = self.consume()
                    op = self.consume()
                    v = self.parse_value()
                    entry = {"operator": op, "value": v} if op != "=" else v
                    if k in nested_dict:
                        if not isinstance(nested_dict[k], list):
                            nested_dict[k] = [nested_dict[k]]
                        nested_dict[k].append(entry)
                    else:
                        nested_dict[k] = entry
                else:
                    item = self.consume()
                    nested_list.append(item)
                    is_pure_list = True

            if self.peek() == "}":
                self.consume()  # eat '}'

            if is_pure_list and not nested_dict:
                return nested_list
            if nested_list:
                nested_dict["_items"] = nested_list
            return nested_dict
        else:
            return self.consume()

    def peek(self) -> Union[str, None]:
        if self.pos < self.length:
            return self.tokens[self.pos]
        return None

    def peek_ahead(self, offset: int) -> Union[str, None]:
        idx = self.pos + offset
        if idx < self.length:
            return self.tokens[idx]
        return None

    def consume(self) -> Union[str, None]:
        token = self.peek()
        if token is not None:
            self.pos += 1
        return token


def parse_clausewitz_file(file_path: str) -> Dict[str, Any]:
    with open(file_path, "r", encoding="utf-8-sig", errors="replace") as f:
        content = f.read()
    tokens = ClausewitzTokenizer.tokenize(content)
    parser = ClausewitzParser(tokens)
    return parser.parse()


def parse_localization_yml(file_path: str) -> Dict[str, str]:
    """Parses Paradox .yml localization files."""
    loc_data = {}
    key_val_pattern = re.compile(r'^\s*([A-Za-z0-9_.\-]+):[0-9]*\s*"(.*)"\s*$')
    with open(file_path, "r", encoding="utf-8-sig", errors="replace") as f:
        for line in f:
            match = key_val_pattern.match(line)
            if match:
                k, v = match.groups()
                loc_data[k] = v.replace("\\n", "\n")
    return loc_data


def main():
    parser = argparse.ArgumentParser(description="Clausewitz to Godot 4 Data Pipeline")
    parser.add_argument("--file", "-f", help="Single .txt or .yml file to parse")
    parser.add_argument("--out", "-o", default="parsed_data.json", help="Output JSON file path")
    args = parser.parse_args()

    if args.file:
        if args.file.endswith(".yml") or args.file.endswith(".yaml"):
            data = parse_localization_yml(args.file)
        else:
            data = parse_clausewitz_file(args.file)

        with open(args.out, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        print(f"[SUCCESS] Parsed {args.file} -> {args.out}")


if __name__ == "__main__":
    main()
