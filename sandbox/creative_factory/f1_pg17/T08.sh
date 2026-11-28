#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")"
[[ "${PGHOST:-}" == 127.0.0.1 && "${PGDATABASE:-}" == lf_creative_f1_ci && "${PGUSER:-}" == postgres ]] || { echo 'T08|FAIL unsafe target'; exit 2; }
[[ -f "${F1_CANDIDATE:-}" && -n "${F1_CANDIDATE_SHA256:-}" ]] || { echo 'T08|FAIL candidate missing'; exit 2; }
printf '%s  %s\n' "$F1_CANDIDATE_SHA256" "$F1_CANDIDATE" | sha256sum -c - >/dev/null
BODY="$(mktemp)"; SQL="$(mktemp)"; trap 'rm -f "$BODY" "$SQL"' EXIT
python3 - "$F1_CANDIDATE" "$BODY" <<'PY'
import pathlib,sys
src=pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").splitlines(True)
non=[i for i,l in enumerate(src) if l.strip() and not l.lstrip().startswith("--")]
if len(non)<2 or src[non[0]].strip()!="BEGIN;" or src[non[-1]].strip()!="COMMIT;":
    raise SystemExit("F1_CANDIDATE_TRANSACTION_BOUNDARY_INVALID")
drop={non[0],non[-1]}
pathlib.Path(sys.argv[2]).write_text("".join(l for i,l in enumerate(src) if i not in drop),encoding="utf-8")
PY
cat >"$SQL" <<SQL
\set ON_ERROR_STOP on
BEGIN;
CREATE TEMP TABLE t08_tables(table_name text PRIMARY KEY,row_count bigint,row_sha256 text);
DO \$snap\$
DECLARE r record; n bigint; h text; table_n integer:=0; row_n bigint:=0;
BEGIN
 FOR r IN
   SELECT c.relname AS table_name
   FROM pg_class c JOIN pg_namespace nsp ON nsp.oid=c.relnamespace
   WHERE nsp.nspname='saly' AND c.relkind IN ('r','p') AND c.relname LIKE 'creative_%'
   ORDER BY c.relname
 LOOP
   EXECUTE format('SELECT count(*), encode(extensions.digest(convert_to(coalesce(string_agg(to_jsonb(t)::text,E''\\n'' ORDER BY to_jsonb(t)::text),''''),''UTF8''),''sha256''),''hex'') FROM saly.%I t',r.table_name)
     INTO n,h;
   INSERT INTO t08_tables VALUES(r.table_name,n,h);
   table_n:=table_n+1; row_n:=row_n+n;
 END LOOP;
 IF table_n<5 OR row_n<1 THEN RAISE EXCEPTION 'T08_INTEGRATED_HISTORY_MISSING'; END IF;
END
\$snap\$;

\i $BODY

DO \$qa\$
DECLARE r record; n bigint; h text;
BEGIN
 FOR r IN SELECT * FROM t08_tables ORDER BY table_name LOOP
   IF to_regclass(format('saly.%I',r.table_name)) IS NULL
   THEN RAISE EXCEPTION 'T08_HISTORICAL_TABLE_REMOVED:%',r.table_name; END IF;
   EXECUTE format('SELECT count(*), encode(extensions.digest(convert_to(coalesce(string_agg(to_jsonb(t)::text,E''\\n'' ORDER BY to_jsonb(t)::text),''''),''UTF8''),''sha256''),''hex'') FROM saly.%I t',r.table_name)
     INTO n,h;
   IF n IS DISTINCT FROM r.row_count OR h IS DISTINCT FROM r.row_sha256
   THEN RAISE EXCEPTION 'T08_HISTORICAL_ROW_HASH_CHANGED:% before=%/% after=%/%',
        r.table_name,r.row_count,r.row_sha256,n,h; END IF;
 END LOOP;
END
\$qa\$;
ROLLBACK;
SQL
psql -X -v ON_ERROR_STOP=1 -f "$SQL" >/dev/null
echo 'T08|PASS'
