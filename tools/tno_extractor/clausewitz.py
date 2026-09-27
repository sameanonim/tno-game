"""
Clausewitz Script (PDX Script) Parser for HOI4 / TNO Mod.
Handles comments (#), quoted strings, comparison operators (=, <, >, <=, >=, !=),
lists of values, repeated keys (e.g. multiple options, victory points), and nested blocks.
"""

import re
from typing import Any, Dict, List, Union, Tuple, Optional


class ClausewitzLexer:
    """Fast regular-expression based lexer for Clausewitz script."""
    
    # Matches comments, quoted strings, operators, braces, or non-whitespace words
    TOKEN_REGEX = re.compile(
        r'(#.*?$)|'                                # 1: Comments
        r'("(?:\\.|[^"\\])*")|'                    # 2: Quoted strings
        r'([<>!=]=|[<>=])|'                        # 3: Operators (=, <=, >=, !=, <, >)
        r'([{}])|'                                 # 4: Braces
        r'([^\s#{}"=<>!]+)',                       # 5: Unquoted words/identifiers
        re.MULTILINE
    )

    @classmethod
    def tokenize(cls, text: str) -> List[str]:
        tokens = []
        for match in cls.TOKEN_REGEX.finditer(text):
            comment, quoted, op, brace, word = match.groups()
            if comment:
                continue
            elif quoted is not None:
                # Strip wrapping quotes and handle escape characters
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
    """Recursive descent AST parser that builds clean Python dicts and lists."""

    def __init__(self, tokens: List[str]):
        self.tokens = tokens
        self.pos = 0
        self.total = len(tokens)

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
        """Parses the entire token stream into a root dictionary."""
        root: Dict[str, Any] = {}
        while self.pos < self.total:
            if self.peek() == "}":
                self.consume()  # Skip unexpected stray closing brace
                continue
            self._parse_statement(root)
        return root

    def _parse_statement(self, container: Dict[str, Any]) -> None:
        key = self.consume()
        if key is None:
            return

        op = self.peek()
        if op in ("=", "<", ">", "<=", ">=", "!=", "?="):
            self.consume()  # eat operator
            val = self._parse_value()
            
            # If operator is not '=', we can store as a condition dict or standard value
            if op != "=":
                val = {"_op": op, "value": val}
            
            self._add_key_val(container, key, val)
        else:
            # Standalone identifier or list item
            if "_items" not in container:
                container["_items"] = []
            container["_items"].append(key)

    def _parse_value(self) -> Any:
        token = self.peek()
        if token == "{":
            self.consume()  # eat '{'
            return self._parse_block()
        else:
            tok = self.consume()
            return self._convert_literal(tok)

    def _parse_block(self) -> Any:
        block_dict: Dict[str, Any] = {}
        block_list: List[Any] = []
        is_pure_list = True

        while self.pos < self.total:
            token = self.peek()
            if token == "}":
                self.consume()  # eat '}'
                break
            
            # Check if this is a key-value pair
            next_token = self.peek(1)
            if next_token in ("=", "<", ">", "<=", ">=", "!=", "?="):
                is_pure_list = False
                key = self.consume()
                op = self.consume()
                val = self._parse_value()
                if op != "=":
                    val = {"_op": op, "value": val}
                self._add_key_val(block_dict, key, val)
            elif token == "{":
                # Nested anonymous block in a list
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

    def _add_key_val(self, target: Dict[str, Any], key: str, val: Any) -> None:
        if key in target:
            existing = target[key]
            if isinstance(existing, list) and not self._is_wrapped_list(existing, key):
                target[key].append(val)
            else:
                target[key] = [existing, val]
        else:
            target[key] = val

    def _is_wrapped_list(self, obj: Any, key: str) -> bool:
        # Helper to avoid flattening distinct structures
        return False

    @staticmethod
    def _convert_literal(val: Optional[str]) -> Any:
        if val is None:
            return None
        # Boolean
        if val.lower() == "yes":
            return True
        if val.lower() == "no":
            return False
        # Integer
        if val.isdigit() or (val.startswith("-") and val[1:].isdigit()):
            try:
                return int(val)
            except ValueError:
                pass
        # Float
        try:
            if "." in val:
                return float(val)
        except ValueError:
            pass
        return val


def parse_clausewitz_text(text: str) -> Dict[str, Any]:
    """Parses Clausewitz script from string."""
    tokens = ClausewitzLexer.tokenize(text)
    parser = ClausewitzParser(tokens)
    return parser.parse()


def parse_clausewitz_file(file_path: str) -> Dict[str, Any]:
    """Parses Clausewitz script from a file with utf-8-sig encoding support."""
    with open(file_path, "r", encoding="utf-8-sig", errors="replace") as f:
        content = f.read()
    return parse_clausewitz_text(content)
