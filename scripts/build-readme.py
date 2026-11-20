#!/usr/bin/env python3
"""Regenerate the generated parts of README.md from prompts/ (prompt files are the single source).

Replaces the content between these marker pairs:
  <!-- shared:start --> / <!-- shared:end -->   -> prompts/_system.md and prompts/_analyse.md
  <!-- table:start -->  / <!-- table:end -->    -> NAME | PROMPT | DESCRIPTION | EXAMPLE
"""
import html
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
README = ROOT / "README.md"
ORDER = [
    "app", "app-livenessProbe", "app-readinessProbe", "app-volumeMounts", "app-cronjob",
    "app-job", "app-multicontainer", "app-resources", "app-secret-env",
]


def cell(text: str) -> str:
    text = html.escape(text.strip(), quote=False)
    text = text.replace("|", "\\|").replace("*", "\\*")
    return "<br>".join(text.splitlines())


def descriptions() -> dict:
    out = {}
    for line in (ROOT / "prompts" / "descriptions.tsv").read_text().splitlines():
        if line.strip():
            mode, name, desc = line.split("\t", 2)
            out[(mode, name)] = desc
    return out


def row(mode: str, name: str, desc: dict) -> str:
    prompt = (ROOT / "prompts" / mode / f"{name}.md").read_text()
    if mode == "generate":
        target, label = f"yaml/{name}.yaml", name
        extra = ""
    else:
        target, label = f"yaml/{name}.fixed.yaml", f"{name} (analyse)"
        extra = f" Input: [original](yaml/original/{name}.yaml)."
    if not (ROOT / target).is_file():
        if "--allow-missing" not in sys.argv:
            sys.exit(f"missing {target}")
        target = f"{target} (pending)"
    return (f"| **{label}** | {cell(prompt)} | {cell(desc[(mode, name)])}{extra} "
            f"| [{target}]({target}) |")


def table() -> str:
    desc = descriptions()
    lines = ["| NAME | PROMPT | DESCRIPTION | EXAMPLE |", "|---|---|---|---|"]
    generate = ORDER[:-1] + ["app-secret", "app-secret-env", "ingress"]
    lines += [row("generate", n, desc) for n in generate]
    lines += [row("analyse", n, desc) for n in ORDER]
    return "\n".join(lines)


def shared() -> str:
    parts = []
    for title, name in (("System prompt (prepended to every prompt)", "_system.md"),
                        ("Analysis instructions (added to every analyse prompt)", "_analyse.md")):
        body = (ROOT / "prompts" / name).read_text().rstrip()
        parts.append(f"**{title}** - [`prompts/{name}`](prompts/{name}):\n\n```text\n{body}\n```")
    return "\n\n".join(parts)


def replace(text: str, marker: str, content: str) -> str:
    pattern = re.compile(rf"(<!-- {marker}:start -->\n).*?(<!-- {marker}:end -->)", re.S)
    if not pattern.search(text):
        sys.exit(f"marker {marker} not found in README.md")
    return pattern.sub(lambda m: m.group(1) + content + "\n" + m.group(2), text)


text = README.read_text()
text = replace(text, "shared", shared())
text = replace(text, "table", table())
README.write_text(text)
print("README.md updated")
