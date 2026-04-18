"""Tiny safe boolean-expression evaluator for distiller routing rules.

Used by skills/builtin/distiller/_distill.py to evaluate
plugin.yaml.knowledge.produces.promote_to_workspace_when entries against
a fact dict. **Never** uses Python eval/exec/compile/__import__ — a
hand-rolled tokenizer + recursive-descent parser handles a tiny grammar:

    expr := orexpr
    orexpr  := andexpr ('or' andexpr)*
    andexpr := notexpr ('and' notexpr)*
    notexpr := 'not' notexpr | atom
    atom    := '(' orexpr ')' | comparison
    comparison := IDENT OP value
    OP   := == | != | >= | <= | > | < | in | 'not in'
    value := STRING | NUMBER | BOOL | LIST
    LIST  := '[' (value (',' value)*)? ']'

Refuses any input containing "__", "import", or unbalanced parens —
defence-in-depth even though the parser would reject them anyway.
"""
from __future__ import annotations

import re
from typing import Any


class ExprError(ValueError):
    pass


_FORBIDDEN_RE = re.compile(r"(__|\bimport\b|\beval\b|\bexec\b|\bcompile\b|`|;)")
_TOKEN_RE = re.compile(
    r"\s*("
    r"[A-Za-z_][A-Za-z_0-9.]*"      # identifier (may be dotted)
    r"|==|!=|>=|<=|>|<"             # comparison ops
    r"|\(|\)|\[|\]|,"               # punctuation
    r"|\"(?:[^\"\\]|\\.)*\""        # double-quoted string
    r"|'(?:[^'\\]|\\.)*'"           # single-quoted string
    r"|-?\d+(?:\.\d+)?"             # number
    r")"
)

_KEYWORDS = {"and", "or", "not", "in", "true", "false", "True", "False"}


def _tokenize(src: str) -> list[str]:
    if _FORBIDDEN_RE.search(src):
        raise ExprError("forbidden token in expression")
    if src.count("(") != src.count(")"):
        raise ExprError("unbalanced parentheses")
    if src.count("[") != src.count("]"):
        raise ExprError("unbalanced brackets")
    tokens: list[str] = []
    pos = 0
    while pos < len(src):
        if src[pos].isspace():
            pos += 1
            continue
        m = _TOKEN_RE.match(src, pos)
        if not m:
            raise ExprError(f"unexpected char at {pos}: {src[pos]!r}")
        tokens.append(m.group(1))
        pos = m.end()
    return tokens


class _Parser:
    def __init__(self, tokens: list[str]) -> None:
        self.tokens = tokens
        self.pos = 0

    def peek(self) -> str | None:
        return self.tokens[self.pos] if self.pos < len(self.tokens) else None

    def eat(self, expected: str | None = None) -> str:
        if self.pos >= len(self.tokens):
            raise ExprError("unexpected end of expression")
        tok = self.tokens[self.pos]
        if expected is not None and tok != expected:
            raise ExprError(f"expected {expected!r}, got {tok!r}")
        self.pos += 1
        return tok

    # Grammar entry
    def parse(self) -> Any:
        node = self._or()
        if self.peek() is not None:
            raise ExprError(f"trailing tokens: {self.tokens[self.pos:]}")
        return node

    def _or(self) -> Any:
        node = self._and()
        while self.peek() == "or":
            self.eat("or")
            node = ("or", node, self._and())
        return node

    def _and(self) -> Any:
        node = self._not()
        while self.peek() == "and":
            self.eat("and")
            node = ("and", node, self._not())
        return node

    def _not(self) -> Any:
        if self.peek() == "not":
            self.eat("not")
            return ("not", self._not())
        return self._atom()

    def _atom(self) -> Any:
        if self.peek() == "(":
            self.eat("(")
            node = self._or()
            self.eat(")")
            return node
        # comparison: IDENT OP value
        ident = self.eat()
        if not _is_identifier(ident):
            raise ExprError(f"expected identifier, got {ident!r}")
        op = self.eat()
        if op == "not":
            self.eat("in")
            op = "not in"
        if op not in {"==", "!=", ">=", "<=", ">", "<", "in"} and op != "not in":
            raise ExprError(f"unsupported operator: {op!r}")
        value = self._value()
        return ("cmp", ident, op, value)

    def _value(self) -> Any:
        tok = self.eat()
        if tok == "[":
            items: list[Any] = []
            if self.peek() != "]":
                items.append(self._scalar(self.eat()))
                while self.peek() == ",":
                    self.eat(",")
                    items.append(self._scalar(self.eat()))
            self.eat("]")
            return items
        return self._scalar(tok)

    def _scalar(self, tok: str) -> Any:
        if (tok.startswith('"') and tok.endswith('"')) or (
            tok.startswith("'") and tok.endswith("'")
        ):
            return _unquote(tok)
        if tok in ("true", "True"):
            return True
        if tok in ("false", "False"):
            return False
        try:
            if "." in tok:
                return float(tok)
            return int(tok)
        except ValueError:
            raise ExprError(f"unrecognised value: {tok!r}")


def _is_identifier(tok: str) -> bool:
    if not tok or tok in _KEYWORDS:
        return False
    return bool(re.fullmatch(r"[A-Za-z_][A-Za-z_0-9.]*", tok))


def _unquote(tok: str) -> str:
    body = tok[1:-1]
    out = []
    i = 0
    while i < len(body):
        c = body[i]
        if c == "\\" and i + 1 < len(body):
            nxt = body[i + 1]
            out.append({"n": "\n", "t": "\t", '"': '"', "'": "'", "\\": "\\"}.get(nxt, nxt))
            i += 2
        else:
            out.append(c)
            i += 1
    return "".join(out)


def _resolve_ident(name: str, ctx: dict) -> Any:
    cur: Any = ctx
    for part in name.split("."):
        if isinstance(cur, dict) and part in cur:
            cur = cur[part]
        else:
            return None
    return cur


def _eval_node(node: Any, ctx: dict) -> bool:
    if not isinstance(node, tuple):
        raise ExprError("malformed AST")
    op = node[0]
    if op == "or":
        return bool(_eval_node(node[1], ctx)) or bool(_eval_node(node[2], ctx))
    if op == "and":
        return bool(_eval_node(node[1], ctx)) and bool(_eval_node(node[2], ctx))
    if op == "not":
        return not bool(_eval_node(node[1], ctx))
    if op == "cmp":
        _, ident, cop, val = node
        left = _resolve_ident(ident, ctx)
        try:
            if cop == "==":
                return left == val
            if cop == "!=":
                return left != val
            if cop == ">":
                return left is not None and left > val
            if cop == "<":
                return left is not None and left < val
            if cop == ">=":
                return left is not None and left >= val
            if cop == "<=":
                return left is not None and left <= val
            if cop == "in":
                return left in val if val is not None else False
            if cop == "not in":
                return left not in val if val is not None else True
        except TypeError:
            return False
    raise ExprError(f"unknown op: {op!r}")


def safe_eval(expr: str, context: dict) -> bool:
    """Evaluate `expr` against `context` and return a bool.

    Raises ExprError on any syntax/safety failure — caller decides
    whether to treat that as "rule did not match" or to bubble up.
    """
    if not isinstance(expr, str) or not expr.strip():
        raise ExprError("empty expression")
    tokens = _tokenize(expr)
    if not tokens:
        raise ExprError("empty expression")
    parser = _Parser(tokens)
    ast = parser.parse()
    return bool(_eval_node(ast, context))
