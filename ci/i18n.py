#!/usr/bin/env python3
"""Перевод оболочки: служебные действия над строками в QML.

  wrap   - обернуть русские строки в Tr.t("…") (запускается после правок QML)
  keys   - вывести все строки, которые оболочка отдаёт на перевод
  check  - каких строк не хватает в shell/i18n/<код>.json
"""
import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LITERAL = re.compile(r'"(?:[^"\\\n]|\\.)*"')
CYRILLIC = re.compile("[А-Яа-яЁё]")
CALL = re.compile(r'Tr\.t\(("(?:[^"\\\n]|\\.)*")\)')
# строки, которые уходят в команды или сравниваются с данными программ: переводить нельзя
KEEP_LINE = re.compile(r"execDetached|\bcommand\b|RegExp|replace\(/|split\(/|L\.push\(|i18n-keep")
# куски сценариев оболочки внутри QML
SHELL_CODE = re.compile(r'echo |\$[A-Za-z0-9({]|\\"\$|awk |printf | \| ')
# Theme.qml: имена тем хранятся в настройках, перевод сломал бы выбранную тему
SKIP_FILES = {"Tr.qml", "Theme.qml"}


def sources():
    return [f for f in sorted(glob.glob(os.path.join(ROOT, "shell", "*.qml")))
            if os.path.basename(f) not in SKIP_FILES]


def comment_start(line):
    """Позиция // вне строки, либо длина строки."""
    quoted = False
    i = 0
    while i < len(line) - 1:
        c = line[i]
        if c == "\\" and quoted:
            i += 2
            continue
        if c == '"':
            quoted = not quoted
        elif not quoted and c == "/" and line[i + 1] == "/":
            return i
        i += 1
    return len(line)


def wrap_line(line):
    if line.lstrip().startswith(("//", "*", "/*", "import ")):
        return line
    end = comment_start(line)
    code, tail = line[:end], line[end:]
    # всё, что правее вызова команды, - её аргументы; надпись левее него переводится
    keep = KEEP_LINE.search(line)
    if keep:
        if keep.group() == "i18n-keep":
            return line
        tail = code[keep.start():] + tail
        code = code[:keep.start()]
    out, pos = [], 0
    for m in LITERAL.finditer(code):
        text = m.group()
        before, after = code[:m.start()], code[m.end():]
        is_key = re.match(r"\s*:", after) and re.search(r"(^|[{,])\s*$", before)
        wrapped = before.endswith("Tr.t(")
        inner = text[1:-1]
        fixed = SHELL_CODE.search(inner) or before.endswith("words: ") or re.search(r'^\s*"(?:[^"\\]|\\.)*":\s*$', before) or (len(inner) <= 3 and inner.isupper())
        out.append(code[pos:m.start()])
        out.append(text if (not CYRILLIC.search(text) or is_key or wrapped or fixed) else "Tr.t(" + text + ")")
        pos = m.end()
    out.append(code[pos:])
    return "".join(out) + tail


def keys():
    found = []
    for f in sources():
        for m in CALL.finditer(open(f, encoding="utf-8").read()):
            k = json.loads(m.group(1))
            if k not in found:
                found.append(k)
    return found


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "check"
    if cmd == "wrap":
        for f in sources():
            old = open(f, encoding="utf-8").read()
            new = "".join(wrap_line(l) for l in old.splitlines(True))
            if new != old:
                open(f, "w", encoding="utf-8").write(new)
                print("обновлён", os.path.basename(f))
    elif cmd == "keys":
        json.dump(keys(), sys.stdout, ensure_ascii=False, indent=0)
    else:
        bad = 0
        wanted = keys()
        for f in sorted(glob.glob(os.path.join(ROOT, "shell", "i18n", "*.json"))):
            have = json.load(open(f, encoding="utf-8"))
            missing = [k for k in wanted if k not in have]
            print("%s: переведено %d из %d" % (os.path.basename(f), len(wanted) - len(missing), len(wanted)))
            for k in missing[:15]:
                print("   нет перевода:", json.dumps(k, ensure_ascii=False))
            bad += len(missing)
        sys.exit(1 if bad and cmd == "strict" else 0)


if __name__ == "__main__":
    main()
