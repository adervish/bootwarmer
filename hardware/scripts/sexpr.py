"""Minimal KiCad s-expression reader/writer."""
import re
_tok = re.compile(r'\s*(\(|\)|"(?:\\.|[^"\\])*"|[^\s()]+)')

class Sym(str):
    """Unquoted atom."""

def parse(text):
    stack = [[]]
    for m in _tok.finditer(text):
        t = m.group(1)
        if t == '(':
            stack.append([])
        elif t == ')':
            x = stack.pop()
            stack[-1].append(x)
        elif t.startswith('"'):
            stack[-1].append(t[1:-1].replace('\\"', '"').replace('\\\\', '\\'))
        else:
            stack[-1].append(Sym(t))
    return stack[0][0]

def dump(x, ind=0):
    if isinstance(x, list):
        simple = all(not isinstance(i, list) for i in x)
        if simple:
            return '(' + ' '.join(dump(i) for i in x) + ')'
        pad = '\n' + '  ' * (ind + 1)
        out = '(' + dump(x[0])
        for i in x[1:]:
            out += (pad + dump(i, ind + 1)) if isinstance(i, list) else (' ' + dump(i))
        return out + '\n' + '  ' * ind + ')'
    if isinstance(x, Sym):
        return str(x)
    if isinstance(x, str):
        return '"' + x.replace('\\', '\\\\').replace('"', '\\"') + '"'
    return str(x)

def find(x, key):
    return [i for i in x[1:] if isinstance(i, list) and i and i[0] == key]

def first(x, key):
    r = find(x, key)
    return r[0] if r else None
