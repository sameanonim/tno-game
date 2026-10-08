"""
High-Performance Clausewitz Script Lexer and AST Parser
======================================================
Robust parsing for Hearts of Iron IV and TNO script files (.txt).
Handles comments, quoted strings, comparison operators, repeated keys, and lists.
"""

from pathlib import Path
import re
from typing import Any, Dict, List, Optional, Tuple, Union


class ClausewitzLexer:
    # Token regular expression matching quoted strings, comments, operators, braces, words
    TOKEN_REGEX = re.compile(
        r'("(?:\\.|[^"\\])*")|'                    # Group 1: Quoted string literal
        r'(#.*?$)|'                                # Group 2: Single-line comment
        r'([<>!=]=|[<>=])|'                        # Group 3: Comparison/assignment operators
        r'([{}])|'                                 # Group 4: Braces
        r'([^\s#{}"=<>!]+)',                       # Group 5: Identifier or literal word
        re.MULTILINE
    )

    @classmethod
    def tokenize(cls, text: str) -> List[str]:
        tokens: List[str] = []
        for match in cls.TOKEN_REGEX.finditer(text):
            quoted, comment, op, brace, word = match.groups()
            if comment:
                continue
            if quoted is not None:
                # Strip outer quotes and unescape
                cleaned = quoted[1:-1].replace('\\"', '"').replace('\\\\', '\\')
                tokens.append(cleaned)
            elif op is not None:
                tokens.append(op)
            elif brace is not None:
                tokens.append(brace)
            elif word is not None:
                tokens.append(word)
        return tokens


class ClausewitzParser:
    """Recursive descent AST builder producing Python dictionaries, lists, and primitives."""

    def __init__(self, tokens: List[str]):
        self.tokens: List[str] = tokens
        self.pos: int = 0
        self.total: int = len(tokens)

    def peek(self, offset: int = 0) -> Optional[str]:
        idx = self.pos + offset
        if idx < self.total:
            return self.tokens[idx]
        return None

    def consume(self) -> Optional[str]:
        if self.pos < self.total:
            tok = self.tokens[self.pos]
            self.pos += 1
            return tok
        return None

    def parse(self) -> Dict[str, Any]:
        root: Dict[str, Any] = {}
        while self.pos < self.total:
            if self.peek() == "}":
                self.consume()  # Skip rogue closing brace
                continue
            self._parse_statement(root)
        return root

    def _parse_statement(self, container: Dict[str, Any]) -> None:
        key = self.consume()
        if key is None:
            return

        op = self.peek()
        if op in ("=", "<", ">", "<=", ">=", "!=", "?="):
            self.consume()  # Consume operator
            val = self._parse_value()

            if op != "=":
                val = {"_op": op, "value": val}

            self._append_key_val(container, key, val)
        else:
            # Standalone identifier or list member
            if "_items" not in container:
                container["_items"] = []
            container["_items"].append(self._convert_literal(key))

    def _parse_value(self) -> Any:
        tok = self.peek()
        if tok == "{":
            self.consume()  # Consume '{'
            return self._parse_block()
        val = self.consume()
        return self._convert_literal(val)

    def _parse_block(self) -> Any:
        block_dict: Dict[str, Any] = {}
        block_list: List[Any] = []
        is_pure_list = True

        while self.pos < self.total:
            tok = self.peek()
            if tok == "}":
                self.consume()  # Consume '}'
                break

            next_tok = self.peek(1)
            if next_tok in ("=", "<", ">", "<=", ">=", "!=", "?="):
                is_pure_list = False
                key = self.consume()
                op = self.consume()
                val = self._parse_value()
                if op != "=":
                    val = {"_op": op, "value": val}
                self._append_key_val(block_dict, key, val)
            elif tok == "{":
                # Nested anonymous block
                is_pure_list = False
                self.consume()
                sub = self._parse_block()
                block_list.append(sub)
            else:
                item = self.consume()
                block_list.append(self._convert_literal(item))

        if is_pure_list and not block_dict:
            return block_list
        if block_list:
            block_dict["_items"] = block_list
        return block_dict

    def _append_key_val(self, target: Dict[str, Any], key: str, val: Any) -> None:
        if key in target:
            existing = target[key]
            if isinstance(existing, list):
                existing.append(val)
            else:
                target[key] = [existing, val]
        else:
            target[key] = val

    @staticmethod
    def _convert_literal(val: Optional[str]) -> Any:
        if val is None:
            return None
        low = val.lower()
        if low == "yes":
            return True
        if low == "no":
            return False
        if val.isdigit() or (val.startswith("-") and val[1:].isdigit()):
            try:
                return int(val)
            except ValueError:
                pass
        try:
            if "." in val:
                return float(val)
        except ValueError:
            pass
        return val


def parse_clausewitz_text(text: str) -> Dict[str, Any]:
    tokens = ClausewitzLexer.tokenize(text)
    parser = ClausewitzParser(tokens)
    return parser.parse()


def parse_clausewitz_file(file_path: Union[str, Path]) -> Dict[str, Any]:
    path = Path(file_path)
    for enc in ("utf-8-sig", "utf-8", "cp1252", "latin-1"):
        try:
            with open(path, "r", encoding=enc) as f:
                content = f.read()
            return parse_clausewitz_text(content)
        except (UnicodeDecodeError, UnicodeError):
            continue
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        content = f.read()
    return parse_clausewitz_text(content)
