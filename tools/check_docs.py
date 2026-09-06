#!/usr/bin/env python3
"""Check budgets, routing, and the simple inline Markdown links used by our docs."""

from pathlib import Path
import re
import sys
from urllib.parse import unquote, urlsplit


ROOT_BUDGET = 8 * 1024
GUIDE_BUDGET = 16 * 1024


def prose(text):
    fence = ""
    lines = []
    for line in text.splitlines():
        marker = re.match(r"^ {0,3}(`{3,}|~{3,})", line)
        if marker:
            run = marker.group(1)
            if not fence:
                fence = run
            elif run[0] == fence[0] and len(run) >= len(fence):
                fence = ""
        elif not fence:
            lines.append(line)
    return "\n".join(lines)


def anchors(text):
    result = set()
    for heading in re.findall(r"^#{1,6} (.+)$", prose(text), flags=re.MULTILINE):
        base = re.sub(r"[^\w -]", "", heading.lower()).replace(" ", "-")
        anchor = base
        suffix = 0
        while anchor in result:
            suffix += 1
            anchor = f"{base}-{suffix}"
        result.add(anchor)
    return result


def links(text):
    return re.findall(r"\[[^\]\n]+\]\(([^)\s]+)\)", prose(text))


def check(root):
    root = root.resolve()
    entry = root / "CLAUDE.md"
    alias = root / "AGENTS.md"
    guides = sorted((root / "docs/agent-guide").glob("*.md"))
    errors = []
    documents = {}

    if not alias.is_symlink() or alias.readlink() != Path("CLAUDE.md"):
        errors.append("AGENTS.md: must be a relative symlink to CLAUDE.md")
    if not guides:
        errors.append("docs/agent-guide: no guides found")

    for path in [entry, root / "README.md", *guides]:
        name = path.relative_to(root)
        try:
            data = path.read_bytes()
            documents[path.resolve()] = data.decode("utf-8")
        except (OSError, UnicodeError) as error:
            errors.append(f"{name}: cannot read document: {error}")
            continue
        budget = ROOT_BUDGET if path == entry else GUIDE_BUDGET if path in guides else None
        if budget is not None and len(data) > budget:
            errors.append(f"{name}: {len(data)} bytes exceeds {budget}-byte budget")

    routed = set()
    for source, content in documents.items():
        for link in links(content):
            url = urlsplit(link)
            if url.scheme or url.netloc:
                continue
            target = (source.parent / unquote(url.path)).resolve() if url.path else source
            if source == entry.resolve():
                routed.add(target)
            label = f"{source.relative_to(root)}: {link}"
            if not target.exists():
                errors.append(f"{label}: missing target")
            elif url.fragment and target.suffix.lower() == ".md":
                try:
                    text = documents[target] if target in documents else target.read_text(encoding="utf-8")
                    if unquote(url.fragment) not in anchors(text):
                        errors.append(f"{label}: missing heading")
                except (OSError, UnicodeError) as error:
                    errors.append(f"{label}: cannot read target: {error}")

    for guide in guides:
        if guide.resolve() not in routed:
            errors.append(f"{guide.relative_to(root)}: not linked from CLAUDE.md")
    return errors


def main():
    root = Path(__file__).resolve().parents[1]
    errors = check(root)
    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1
    size = (root / "CLAUDE.md").stat().st_size
    count = len(list((root / "docs/agent-guide").glob("*.md")))
    print(f"Docs OK: root {size}/{ROOT_BUDGET} bytes; {count} guides; links, routing, and symlink valid")
    return 0


if __name__ == "__main__":
    sys.exit(main())
