#!/usr/bin/env bash
set -Eeuo pipefail
[[ "${PGHOST:-}" == 127.0.0.1 && "${PGDATABASE:-}" == lf_creative_f1_ci && "${PGUSER:-}" == postgres ]] || { echo 'T08|FAIL unsafe'; exit 2; }
tables="$(PGDATABASE=lf_creative_f1_baseline psql -XAt -v ON_ERROR_STOP=1 -c "select c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='saly' and c.relkind in ('r','p') and c.relname like 'creative_%' order by c.relname")"
[[ -n "$tables" ]] || { echo 'T08|FAIL no creative tables'; exit 1; }
while IFS= read -r t; do
  [[ "$t" =~ ^creative_[a-z0-9_]+$ ]] || { echo "T08|FAIL unsafe table $t"; exit 1; }
  q="select count(*)::text||'|'||encode(extensions.digest(convert_to(coalesce(string_agg(to_jsonb(x)::text,E'\\n' order by to_jsonb(x)::text),''),'UTF8'),'sha256'),'hex') from saly.\"$t\" x"
  b="$(PGDATABASE=lf_creative_f1_baseline psql -XAt -v ON_ERROR_STOP=1 -c "$q")"
  c="$(PGDATABASE=lf_creative_f1_candidate psql -XAt -v ON_ERROR_STOP=1 -c "$q")"
  [[ "$b" == "$c" ]] || { echo "T08|FAIL $t baseline=$b candidate=$c"; exit 1; }
done <<<"$tables"
echo 'T08|PASS'
