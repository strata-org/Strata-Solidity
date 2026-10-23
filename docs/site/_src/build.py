#!/usr/bin/env python3
"""Build the StrataSolidity website: the landing page and the user guide.

Sources:
  docs/guide/src/SUMMARY.md + *.md   the guide content (single source of
                                      truth, shared with the mdBook build)
  docs/site/_src/templates/          landing page and guide page shell
  docs/site/_src/examples/*.sol,.out real contracts and real strataSolidity
                                      output (refresh with capture_outputs.py)

Output, at the site root (docs/site/):
  index.html, docs/*.html, assets/search-index.js

Usage:  python3 docs/site/_src/build.py      (needs: pip install -r docs/site/requirements.txt)
"""
import html
import json
import re
from pathlib import Path

import markdown
from pygments import highlight
from pygments.formatters import HtmlFormatter
from pygments.lexers import get_lexer_by_name

SRC = Path(__file__).resolve().parent
SITE = SRC.parent
REPO = SITE.parents[1]
DOCS_SRC = REPO / "docs" / "guide" / "src"
DOCS_OUT = SITE / "docs"
EXAMPLES = SRC / "examples"
REPO_URL = "https://github.com/strata-org/Strata-Solidity"
GUIDE_SRC_URL = f"{REPO_URL}/blob/main/docs/guide/src"

SPEC_RE = re.compile(r"@custom:strata(\s+)(requires|ensures|invariant|modifies|loop-invariant|forall|exists)\b")


def mark_specs(code_html: str) -> str:
    """Make @custom:strata annotations stand out inside highlighted comments."""
    return SPEC_RE.sub(r'<span class="spec-tag">@custom:strata</span>\1<span class="spec-kw">\2</span>', code_html)


def render_code(code: str, lang: str = "") -> str:
    """Highlighted block for code, plain block for tool output."""
    if lang:
        lexer = get_lexer_by_name(lang)
        body = highlight(code, lexer, HtmlFormatter(nowrap=True))
        body = mark_specs(body) if lang == "solidity" else body
        return f'<div class="code" data-lang="{lang}"><pre><code>{body}</code></pre></div>'
    return f'<div class="code code--output"><pre><code>{html.escape(code)}</code></pre></div>'


def parse_summary():
    """Return the ordered chapter list: [{title, src, section}]."""
    chapters, section = [], ""
    for line in (DOCS_SRC / "SUMMARY.md").read_text().splitlines():
        if line.startswith("# ") and line.strip() != "# Summary":
            section = line[2:].strip()
        m = re.match(r"\s*-?\s*\[(.+?)\]\(\./(.+?\.md)\)", line)
        if m:
            chapters.append({"title": m.group(1), "src": m.group(2), "section": section})
    for c in chapters:
        c["out"] = "index.html" if c["src"] == "overview.md" else c["src"].replace(".md", ".html")
    return chapters


def md_to_html(text: str, link_map: dict) -> tuple[str, list, str]:
    """Markdown to HTML, with fenced code highlighted by render_code()."""
    blocks = []

    def stash(m):
        blocks.append(render_code(m.group(2).rstrip("\n"), (m.group(1) or "").strip()))
        return f"\n\nCODEBLOCK{len(blocks) - 1}\n\n"

    # Fenced code first, including fences indented inside list items.
    def stash_indented(m):
        indent = m.group(1)
        code = re.sub(rf"(?m)^{indent}", "", m.group(3))
        blocks.append(render_code(code.rstrip("\n"), (m.group(2) or "").strip()))
        return f"{indent}CODEBLOCK{len(blocks) - 1}"

    text = re.sub(r"(?m)^( +)```(\w*)\n(.*?)^\1```", stash_indented, text, flags=re.S)
    text = re.sub(r"(?m)^```(\w*)\n(.*?)^```", stash, text, flags=re.S)

    md = markdown.Markdown(
        extensions=["tables", "toc", "smarty", "attr_list", "sane_lists"],
        extension_configs={"toc": {"permalink": "#", "permalink_class": "anchor", "permalink_title": "Link to this section", "toc_depth": "2-3"}},
    )
    out = md.convert(text)
    for i, block in enumerate(blocks):
        out = out.replace(f"<p>CODEBLOCK{i}</p>", block).replace(f"CODEBLOCK{i}", block)

    def relink(m):
        target, anchor = m.group(1), m.group(2) or ""
        return f'href="{link_map.get(target, target)}{anchor}"'

    out = re.sub(r'href="\./([\w-]+\.md)(#[\w-]+)?"', relink, out)
    out = re.sub(r'href="(https?://[^"]+)"', r'href="\1" rel="noopener"', out)
    out = out.replace("<table>", '<div class="table-wrap"><table>').replace("</table>", "</table></div>")
    title = re.search(r"<h1[^>]*>(.*?)</h1>", out, re.S)
    title_text = re.sub(r"<[^>]+>", "", title.group(1)).replace("#", "").strip() if title else ""
    return out, md.toc_tokens, title_text


def nav_html(chapters, current):
    parts, section = ['<ul class="nav-list">'], None
    for c in chapters:
        if c["section"] != section:
            if section is not None:
                parts.append("</ul></li>")
            section = c["section"]
            if section:
                parts.append(f'<li class="nav-section"><span class="nav-heading">{html.escape(section)}</span><ul>')
            else:
                parts.append("<li><ul>")
        here = ' aria-current="page"' if c is current else ""
        parts.append(f'<li><a href="{c["out"]}"{here}>{html.escape(c["title"])}</a></li>')
    parts.append("</ul></li></ul>")
    return "".join(parts)


def toc_html(tokens):
    items = []
    for t in tokens:
        for h2 in t.get("children", []) if t["level"] == 1 else [t]:
            items.append(f'<li><a href="#{h2["id"]}">{html.escape(html.unescape(h2["name"]))}</a></li>')
    return f'<ul>{"".join(items)}</ul>' if items else ""


def plain_text(fragment: str) -> str:
    text = re.sub(r"<(script|style)[^>]*>.*?</\1>", " ", fragment, flags=re.S)
    text = re.sub(r"<[^>]+>", " ", text)
    return re.sub(r"\s+", " ", html.unescape(text)).strip()


def fill(template: str, values: dict) -> str:
    def sub(m):
        key = m.group(1)
        if key not in values:
            raise KeyError(f"template placeholder {{{{{key}}}}} has no value")
        return values[key]
    return re.sub(r"\{\{([\w:.-]+)\}\}", sub, template)


def build_docs():
    chapters = parse_summary()
    link_map = {c["src"]: c["out"] for c in chapters}
    shell = (SRC / "templates" / "doc.html").read_text()
    DOCS_OUT.mkdir(exist_ok=True)
    index = []
    for i, c in enumerate(chapters):
        body, tokens, h1 = md_to_html((DOCS_SRC / c["src"]).read_text(), link_map)
        prev_c = chapters[i - 1] if i else None
        next_c = chapters[i + 1] if i + 1 < len(chapters) else None
        pager = ""
        if prev_c:
            pager += f'<a class="pager__prev" href="{prev_c["out"]}"><span class="caption">Previous</span>{html.escape(prev_c["title"])}</a>'
        if next_c:
            pager += f'<a class="pager__next" href="{next_c["out"]}"><span class="caption">Next</span>{html.escape(next_c["title"])}</a>'
        page = fill(shell, {
            "title": html.escape(h1 or c["title"]),
            "nav": nav_html(chapters, c),
            "content": body,
            "toc": toc_html(tokens),
            "pager": pager,
            "section": html.escape(c["section"] or "Guide"),
            "source": f'{GUIDE_SRC_URL}/{c["src"]}',
        })
        (DOCS_OUT / c["out"]).write_text(page)
        sections = [{"id": t["id"], "name": html.unescape(t["name"])} for t in tokens for t in ([t] + t.get("children", []))]
        index.append({"title": h1 or c["title"], "url": c["out"], "section": c["section"], "headings": sections, "text": plain_text(body)[:6000]})
    (SITE / "assets" / "search-index.js").write_text("window.SEARCH_INDEX = " + json.dumps(index, ensure_ascii=False) + ";\n")
    return chapters


def build_landing():
    meta = json.loads((EXAMPLES / "outputs.json").read_text())
    values = {"commit": meta["commit"]}
    for sol in EXAMPLES.glob("*.sol"):
        values[f"code:{sol.stem}"] = render_code(sol.read_text().strip(), "solidity")
        values[f"out:{sol.stem}"] = render_code(sol.with_suffix(".out").read_text().strip())
    values["code:quickstart"] = render_code(
        "git clone --recurse-submodules https://github.com/strata-org/Strata-Solidity.git\n"
        "cd Strata-Solidity\nlake build\nTools/Solidity/scripts/strata-verify.sh contract.sol", "bash")
    (SITE / "index.html").write_text(fill((SRC / "templates" / "landing.html").read_text(), values))


def main():
    chapters = build_docs()
    build_landing()
    print(f"built index.html and {len(chapters)} guide pages in {DOCS_OUT.relative_to(REPO)}/")


if __name__ == "__main__":
    main()
