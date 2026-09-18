-- AUD FREEZE VERIFY V1
-- Read-only. No DDL/DML.
-- Baseline: main dafe10a6a730d63bc59ce036360f214cd6fd8d96
-- Expected schema fp: 56c2af889d3f6a4781b1ac74ba7da5bb over public+private / 3993 columns.
select
  count(*)::bigint as schema_column_count,
  md5(string_agg(
    table_schema||'.'||table_name||'.'||column_name||':'||data_type,
    '|' order by table_schema,table_name,ordinal_position
  )) as schema_fp
from information_schema.columns
where table_schema in ('public','private');
