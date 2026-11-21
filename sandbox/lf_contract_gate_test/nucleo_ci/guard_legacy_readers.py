#!/usr/bin/env python3
"""A4: reject new SQL function definitions that read LF's legacy rules directly.

Only added/changed definitions in production SQL are inspected. Old unchanged
definitions are not retroactively rejected. No database access or credentials.
The lexer handles SQL comments, quoted identifiers, dollar/SQL string bodies,
and relation positions; dynamic queries with unresolved relation names fail
closed for newly introduced definitions, not for old unchanged code.
"""
import argparse
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
DOLLAR = re.compile(r"\$(?:[A-Za-z_][A-Za-z_0-9]*)?\$")
WORD = re.compile(r"[A-Za-z_\u0080-\uffff][\w$\u0080-\uffff]*")
END_FROM = {"where", "group", "order", "having", "limit", "offset",
            "fetch", "union", "intersect", "except", "returning", "window",
            "for", "loop", "into", "set", "end", ";"}

def tokens(sql):
    out = []
    i = 0
    while i < len(sql):
        c = sql[i]
        if c.isspace():
            i += 1
            continue
        if sql.startswith("--", i):
            j = sql.find("\n", i)
            i = len(sql) if j < 0 else j + 1
            continue
        if sql.startswith("/*", i):
            depth = 1
            j = i + 2
            while j < len(sql) and depth:
                if sql.startswith("/*", j):
                    depth += 1
                    j += 2
                elif sql.startswith("*/", j):
                    depth -= 1
                    j += 2
                else:
                    j += 1
            if depth:
                raise ValueError("unterminated SQL comment")
            i = j
            continue
        m = DOLLAR.match(sql, i)
        if m:
            q = m.group()
            j = sql.find(q, m.end())
            if j < 0:
                raise ValueError("unterminated SQL dollar string")
            out.append(("str", sql[m.end():j]))
            i = j + len(q)
            continue
        if c in ("'", '"'):
            j = i + 1
            v = []
            while j < len(sql):
                if sql[j] == c:
                    if sql[j:j+2] == c * 2:
                        v.append(c)
                        j += 2
                        continue
                    break
                v.append(sql[j])
                j += 1
            else:
                raise ValueError("unterminated SQL quote")
            out.append(("str" if c == "'" else "id", "".join(v)))
            i = j + 1
            continue
        m = WORD.match(sql, i)
        if m:
            out.append(("id", m.group().lower()))
            i = m.end()
        else:
            out.append(("punct", c))
            i += 1
    return out

def vals(t):
    return [v if k != "str" else "<string>" for k, v in t]

def definitions(text):
    # Dollar and SQL string bodies are single lexer tokens. SQL standard
    # BEGIN ATOMIC blocks may contain semicolons; keep those inside the definition.
    ts = tokens(text)
    out = []
    i = 0
    while i < len(ts):
        if ts[i] != ("id", "create"):
            i += 1
            continue
        j = i + 1
        if vals(ts[j:j+2]) == ["or", "replace"]:
            j += 2
        if j >= len(ts) or ts[j] != ("id", "function"):
            i += 1
            continue
        j += 1
        name = vals(ts[j:j+3])
        name = ".".join((name[0], name[2])) if len(name) >= 3 and name[1] == "." else name[0]
        end = j
        atomic = 0
        parens = 0
        while end < len(ts):
            x = ts[end]
            if vals(ts[end:end+2]) == ["begin", "atomic"]:
                atomic += 1
            elif atomic and x == ("id", "case"):
                atomic += 1
            elif atomic and x == ("id", "end"):
                atomic -= 1
            elif x == ("punct", "("):
                parens += 1
            elif x == ("punct", ")"):
                parens -= 1
            elif not atomic and not parens and x == ("punct", ";"):
                end += 1
                break
            end += 1
        out.append((name, tuple(ts[i:end])))
        i = end
    return out

def relation(t, i, bare):
    while i < len(t) and t[i] in (("id", "only"), ("id", "lateral"), ("punct", "(")):
        i += 1
    if t[i:i+3] == [("id", "lf_ops"), ("punct", "."), ("id", "reglas")]:
        return True
    if bare and t[i:i+1] == [("id", "reglas")] and t[i+1:i+2] not in ([("punct", ".")], [("punct", "(")]):
        return True
    return False

def scans_relation(t, bare):
    depth = 0
    active = {}
    prev = ""
    for i, (k, x) in enumerate(t):
        if k == "str":
            prev = "<string>"
            continue
        if k == "punct" and x == "(":
            depth += 1
        elif k == "punct" and x == ")":
            active.pop(depth, None)
            depth -= 1
        elif x in END_FROM:
            active.pop(depth, None)
        elif k == "id" and x in ("from", "join", "table", "using"):
            # DELETE FROM is a writer target, not the A4 reader contract.
            if not (x == "from" and prev == "delete"):
                if relation(t, i+1, bare):
                    return True
            if x in ("from", "join", "using"):
                active[depth] = True
        elif x == "," and active.get(depth) and relation(t, i+1, bare):
            return True
        prev = x
    return False

def scan_body(t, bare):
    if scans_relation(t, bare):
        return "DIRECT_LEGACY_READ"
    for k, value in t:
        if k == "str" and re.search(r"\b(select|from|join|table|using)\b", value, re.I):
            try:
                if scans_relation(tokens(value), bare):
                    return "DIRECT_LEGACY_READ"
            except ValueError:
                # A dynamic fragment is checked by its EXECUTE expression below.
                pass
    for i, tok in enumerate(t):
        if tok != ("id", "execute"):
            continue
        # SQL PREPARE/EXECUTE and PLpgSQL EXECUTE are treated conservatively;
        # do not allow a new unresolved query to silently bypass the reader gate.
        j = i + 1
        while j < len(t) and t[j] != ("punct", ";"):
            j += 1
        expr = t[i+1:j]
        if not expr:
            return "UNRESOLVED_DYNAMIC_SQL"
        # Literal SQL (without concatenating unknown strings).
        if expr[0][0] == "str":
            if any(expr[z:z+2] == [("punct", "|"), ("punct", "|")] for z in range(len(expr))):
                return "UNRESOLVED_DYNAMIC_SQL"
            continue
        # Explicit literal format template. A relation derived from %I/%s
        # cannot be proven safe by static text, even when current args look safe.
        if len(expr) >= 3 and expr[:2] == [("id", "format"), ("punct", "(")] and expr[2][0] == "str":
            template = expr[2][1]
            if re.search(r"%(?:\d+\$)?(?:I|s)", template):
                return "UNRESOLVED_DYNAMIC_SQL"
            continue
        return "UNRESOLVED_DYNAMIC_SQL"
    return None

def violation(defn):
    name, raw = defn
    t = list(raw)
    v = vals(t)
    # A bare reglas can resolve to legacy through runtime search_path.
    # Only an explicitly declared SALY-only path is a distinct instance.
    bare = True
    for i in range(len(v)-2):
        if v[i:i+2] == ["set", "search_path"]:
            path = []
            for x in v[i+2:]:
                if x in ("as", "language", "security", "stable", "volatile", "immutable", ";", "<string>"):
                    break
                path.append(x)
            bare = not ("saly" in path and "lf_ops" not in path)
    # AS body is a literal, do not confuse function comments/options with SQL.
    for i in range(len(t)-1):
        if t[i] == ("id", "as") and t[i+1][0] == "str":
            if "plpgsql" not in v and "sql" not in v:
                return None
            return scan_body(tokens(t[i+1][1]), bare)
    # SQL standard bodies (RETURN expression / BEGIN ATOMIC).
    return scan_body(t, bare)

def check(old, new):
    previous = set(definitions(old)) if old else set()
    return [(name, reason) for d in definitions(new) if d not in previous
            for name in [d[0]] for reason in [violation(d)] if reason]

def git(*args, optional=False):
    p = subprocess.run(["git", *args], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    if p.returncode:
        if optional:
            return None
        raise RuntimeError(p.stderr.decode("utf-8", errors="replace"))
    return p.stdout.decode("utf-8")

def production_sql(path):
    return path.endswith(".sql") and path.startswith(("supabase/migrations/", "supabase/functions/"))

def self_test():
    def f(body, scope="lf_ops", attrs=""):
        return f"CREATE OR REPLACE FUNCTION {scope}.a4_probe() RETURNS integer LANGUAGE plpgsql {attrs} AS $f$ BEGIN {body}; RETURN 1; END $f$;"
    good = [
        f("PERFORM * FROM lf_ops.v_reglas_compat_v1"),
        f("PERFORM * FROM lf_ops.nucleo_reglas_efectivas_v1('GLOBAL')"),
        f("PERFORM * FROM saly.reglas"),
        f("PERFORM * FROM reglas", "saly", "SET search_path = pg_catalog, saly"),
        f("PERFORM 1 /* FROM lf_ops.reglas */"),
        f("INSERT INTO lf_ops.reglas(codigo) VALUES ('a')"),
        f("UPDATE lf_ops.reglas SET titulo='a'"),
        f("DELETE FROM lf_ops.reglas WHERE codigo='a'"),
        "CREATE FUNCTION public.a4_std() RETURNS integer LANGUAGE sql RETURN (SELECT 1);",
    ]
    bad = [
        f("PERFORM * FROM lf_ops.reglas"),
        f('PERFORM * FROM "lf_ops" /* gap */ . "reglas"'),
        f("PERFORM * FROM ONLY (lf_ops.reglas)"),
        f("PERFORM * FROM public.x JOIN lf_ops.reglas ON true"),
        f("PERFORM * FROM public.x, lf_ops.reglas"),
        f("PERFORM * FROM (SELECT * FROM lf_ops.reglas) a"),
        f("PERFORM * FROM reglas"),
        f("EXECUTE 'SELECT * FROM lf_ops.reglas'"),
        f("EXECUTE format('SELECT * FROM %I.%I', 'lf_ops', 'reglas')"),
        f("EXECUTE q"),
        "CREATE FUNCTION public.a4_std() RETURNS integer LANGUAGE sql RETURN (SELECT count(*)::int FROM lf_ops.reglas);",
        "CREATE FUNCTION public.a4_std2() RETURNS integer LANGUAGE sql BEGIN ATOMIC SELECT 1; SELECT count(*)::int FROM lf_ops.reglas; END;",
        "CREATE FUNCTION public.a4_text() RETURNS integer LANGUAGE sql AS 'SELECT count(*)::int FROM lf_ops.reglas';",
    ]
    for s in good:
        if check("", s):
            raise AssertionError("A4 false positive: " + s)
    for s in bad:
        if not check("", s):
            raise AssertionError("A4 false negative: " + s)
    if check(bad[0], bad[0] + "\n" + good[0]):
        raise AssertionError("A4 unchanged grandfathered function blocked")
    if not check(good[0], bad[0]):
        raise AssertionError("A4 newly introduced legacy read in replacement missed")
    print(f"A4_SELFTEST_PASS positive={len(good)+1} negative={len(bad)+1}", flush=True)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base")
    ap.add_argument("--head")
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--force-fail", action="store_true")
    args = ap.parse_args()
    self_test()
    if args.self_test:
        return
    if not args.base or not args.head or git("rev-parse", "HEAD").strip() != args.head:
        raise RuntimeError("A4_EXACT_HEAD_REQUIRED")
    changed = git("diff", "--name-only", args.base, args.head, "--").splitlines()
    findings = []
    files = 0
    for path in changed:
        if not production_sql(path):
            continue
        new = git("show", f"{args.head}:{path}", optional=True)
        if new is None:
            continue
        old = git("show", f"{args.base}:{path}", optional=True) or ""
        files += 1
        for name, why in check(old, new):
            findings.append((path, name, why))
    if args.force_fail:
        probe = "CREATE FUNCTION lf_ops.zz_a4_negative() RETURNS bigint LANGUAGE sql AS $$ SELECT count(*) FROM lf_ops.reglas $$;"
        for name, why in check("", probe):
            findings.append(("forced-negative-probe.sql", name, why))
        if not findings:
            raise RuntimeError("A4_NEGATIVE_PROBE_NOT_DETECTED")
    if findings:
        for path, name, why in findings:
            print(f"A4_BLOCK {why} {path} {name}", file=sys.stderr)
        raise SystemExit(1)
    print(f"A4_PASS {files} changed production SQL files; no new direct legacy readers")

if __name__ == "__main__":
    main()
