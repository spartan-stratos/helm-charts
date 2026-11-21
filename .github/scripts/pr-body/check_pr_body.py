#!/usr/bin/env python3
"""Validate a PR body: check_pr_body.py <template> <body-file>."""
import re
import sys

MAX_PROSE_WORDS = 300
BANNED_DASHES = re.compile("[\u2013\u2014\u2015]")
ATTRIBUTION = re.compile(
    r"\U0001F916|co-authored-by\b|generated\s+(?:with|by)\s+\[?(?:claude|codex|copilot|chatgpt|gpt|gemini|cursor|an?\s+(?:ai|llm))\b",
    re.IGNORECASE,
)
INTERNAL = re.compile(
    r"\.agent/|~/\.claude|~/\.backlog|/tmp/claude|\btkt(?:#|-)\d+",
    re.IGNORECASE,
)
COMMENT = re.compile(r"<!--.*?-->", re.DOTALL)
FENCE = re.compile(r"^(`{3,}|~{3,})[^\n]*\n.*?^\1[ \t]*$", re.MULTILINE | re.DOTALL)
HEADING = re.compile(r"^## +(.+?)[ \t]*$", re.MULTILINE)
CHECKBOX = re.compile(r"^\s*[-*+]\s+\[[ xX]\].*$", re.MULTILINE)
TABLE = re.compile(r"^[ \t]*\|.*\|[ \t]*$", re.MULTILINE)


def sections(text):
    masked = FENCE.sub(lambda m: re.sub(r"[^\n]", " ", m.group(0)), text)
    marks = list(HEADING.finditer(masked))
    return [
        (m.group(1), text[m.end():marks[i + 1].start() if i + 1 < len(marks) else len(text)])
        for i, m in enumerate(marks)
    ]


def check(template, body):
    errors = []
    required = [name for name, _ in sections(COMMENT.sub("", template))]
    body = COMMENT.sub("", body.replace("\r\n", "\n"))
    found = sections(body)
    names = [name for name, _ in found]
    missing = [name for name in required if name not in names]
    if missing:
        errors.append("missing template sections: " + ", ".join(missing))
    elif [name for name in names if name in required] != required:
        errors.append("template sections are out of order; expected: " + ", ".join(required))
    for name, content in found:
        if name in required and not content.strip():
            errors.append(f'section "{name}" is empty')

    types = FENCE.sub("", dict(found).get("Types of Changes", ""))
    if not re.search(r"^\s*[-*+]\s+\[x\]", types, re.MULTILINE | re.IGNORECASE):
        errors.append("tick at least one Types of Changes checkbox")
    if BANNED_DASHES.search(body):
        errors.append("contains an en-dash, em-dash or horizontal bar; use a plain hyphen")
    if ATTRIBUTION.search(body):
        errors.append("contains AI or tool attribution")
    if INTERNAL.search(body):
        errors.append("contains internal-only references")
    has_mermaid = any(re.match(r"(?:`{3,}|~{3,})mermaid[ \t]*\n", m.group()) for m in FENCE.finditer(body))
    if not has_mermaid and not re.search(r"^No diagram:", body, re.MULTILINE):
        errors.append("include a Mermaid fenced block or a line starting No diagram:")
    prose = len(TABLE.sub("", CHECKBOX.sub("", FENCE.sub("", body))).split())
    if prose > MAX_PROSE_WORDS:
        errors.append(f"{prose} prose words; the limit is {MAX_PROSE_WORDS}")
    return errors


def main():
    template, body_file = sys.argv[1], sys.argv[2]
    with open(template, encoding="utf-8") as source:
        template = source.read()
    with open(body_file, encoding="utf-8") as source:
        body = source.read()
    errors = check(template, body)
    for error in errors:
        print(f"::error title=PR body::{error}")
    if errors:
        print("Rules: AGENTS.md, section 'Pull requests'. Edit the PR description; this check re-runs on edit.")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
