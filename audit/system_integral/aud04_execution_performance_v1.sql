-- AUD-4 execution & performance database runner v1
-- Read-only. Metrics are observational; cumulative pg_stat counters are labeled as such.
with
qstats as (
  select s.calls,s.total_exec_time,s.mean_exec_time,s.rows,s.shared_blks_hit,s.shared_blks_read,s.temp_blks_written,
         regexp_replace(s.query,'\s+',' ','g') query_text,
         case when s.calls>0 then s.rows::numeric/s.calls else null end rows_per_call,
         case when s.calls>0 then (s.shared_blks_hit+s.shared_blks_read)::numeric/s.calls else null end blocks_per_call
  from extensions.pg_stat_statements s
  join pg_database d on d.oid=s.dbid
  where d.datname=current_database() and s.query not ilike '%pg_stat_statements%'
),
query_hot as (
  select * from qstats where calls>=2 and mean_exec_time>=1000 order by mean_exec_time desc
),
broad as (
  select * from qstats
  where calls>=5
    and (query_text ~* 'select\s+\*' or coalesce(rows_per_call,0)>=1000)
  order by coalesce(rows_per_call,0) desc,mean_exec_time desc
),
table_stats as (
  select schemaname,relname,seq_scan,seq_tup_read,idx_scan,idx_tup_fetch,n_live_tup,n_dead_tup,
         pg_total_relation_size(relid) total_bytes,relid
  from pg_stat_user_tables
  where schemaname in ('public','private','programacion')
),
seq_hot as (
  select *,case when n_live_tup>0 then seq_tup_read::numeric/n_live_tup else null end seq_reads_per_live_row
  from table_stats
  where n_live_tup>=50 and seq_tup_read>=10000
  order by seq_tup_read desc
),
fk as (
 select con.oid,ns.nspname schema_name,cl.relname table_name,con.conname,con.conkey attnums,cl.oid relid
 from pg_constraint con join pg_class cl on cl.oid=con.conrelid join pg_namespace ns on ns.oid=cl.relnamespace
 where con.contype='f' and ns.nspname in ('public','private','programacion')
),
fk_missing as (
 select f.*,coalesce(st.n_live_tup,0) n_live_tup,coalesce(st.seq_tup_read,0) seq_tup_read,
        coalesce(st.idx_scan,0) idx_scan,pg_total_relation_size(f.relid) total_bytes
 from fk f left join pg_stat_user_tables st on st.relid=f.relid
 where not exists (
   select 1 from pg_index i
   where i.indrelid=f.relid and i.indisvalid
     and (i.indkey::smallint[])[0:cardinality(f.attnums)-1]=f.attnums
 )
),
unused_indexes as (
 select ns.nspname schema_name,t.relname table_name,i.relname index_name,
        coalesce(si.idx_scan,0) idx_scan,pg_relation_size(i.oid) index_bytes
 from pg_index ix
 join pg_class i on i.oid=ix.indexrelid
 join pg_class t on t.oid=ix.indrelid
 join pg_namespace ns on ns.oid=t.relnamespace
 left join pg_stat_user_indexes si on si.indexrelid=i.oid
 where ns.nspname in ('public','private','programacion')
   and not ix.indisprimary and not ix.indisunique
   and coalesce(si.idx_scan,0)=0
   and pg_relation_size(i.oid)>=1048576
),
payload_op as (
 select pg_column_size(manifest) manifest_bytes,pg_column_size(checkpoint_payload) checkpoint_bytes
 from public.lf_operation_execution
),
payload_step as (
 select pg_column_size(evidence_payload) evidence_bytes from public.lf_operation_execution_steps
),
completed as (
 select operation_code,extract(epoch from (completed_at-started_at)) seconds
 from public.lf_operation_execution
 where completed_at is not null and started_at is not null and started_at>=now()-interval '30 days'
),
duration_agg as (
 select operation_code,count(*) n,
        percentile_cont(.5) within group(order by seconds) p50_s,
        percentile_cont(.95) within group(order by seconds) p95_s,
        max(seconds) max_s
 from completed group by operation_code
),
step_gaps as (
 select e.operation_code,s.execution_id,s.step_id,s.observed_at,
        extract(epoch from (s.observed_at-lag(s.observed_at) over(partition by s.execution_id order by s.step_order,s.observed_at))) gap_s
 from public.lf_operation_execution_steps s
 join public.lf_operation_execution e using(execution_id)
 where s.observed_at>=now()-interval '30 days'
),
gap_agg as (
 select operation_code,count(*) filter(where gap_s is not null) gaps,
        percentile_cont(.5) within group(order by gap_s) filter(where gap_s is not null) p50_gap_s,
        percentile_cont(.95) within group(order by gap_s) filter(where gap_s is not null) p95_gap_s,
        max(gap_s) max_gap_s
 from step_gaps group by operation_code
),
stuck as (
 select execution_id,operation_code,status,started_at,lease_expires_at,
        extract(epoch from (now()-started_at)) age_s
 from public.lf_operation_execution
 where completed_at is null and status not in ('COMPLETED','PASS_CLOSED','CLOSED')
),
cache_stats as (
 select calls,total_exec_time,mean_exec_time,rows,left(query_text,400) query_sample
 from qstats where query_text ilike '%cached%' or query_text ilike '%cache%'
 order by total_exec_time desc
)
select jsonb_build_object(
 'pg_stat',jsonb_build_object(
   'stats_reset',(select stats_reset from pg_stat_database where datname=current_database()),
   'statement_count',(select count(*) from qstats),
   'high_mean_ge_1s_calls_ge_2',(select count(*) from query_hot),
   'broad_or_high_rows_candidates',(select count(*) from broad),
   'top_query_hotspots',coalesce((select jsonb_agg(jsonb_build_object(
      'calls',calls,'mean_ms',mean_exec_time,'total_ms',total_exec_time,'rows',rows,
      'rows_per_call',rows_per_call,'blocks_per_call',blocks_per_call,'query_sample',left(query_text,300)
   ) order by mean_exec_time desc) from (select * from query_hot limit 20)x),'[]'::jsonb),
   'top_broad_candidates',coalesce((select jsonb_agg(jsonb_build_object(
      'calls',calls,'mean_ms',mean_exec_time,'rows_per_call',rows_per_call,'query_sample',left(query_text,300)
   ) order by rows_per_call desc nulls last) from (select * from broad limit 20)x),'[]'::jsonb)
 ),
 'index_scan',jsonb_build_object(
   'tables_considered',(select count(*) from table_stats),
   'seq_hot_candidates',(select count(*) from seq_hot),
   'top_seq_hot',coalesce((select jsonb_agg(jsonb_build_object(
      'schema',schemaname,'table',relname,'seq_scan',seq_scan,'seq_tup_read',seq_tup_read,
      'idx_scan',idx_scan,'live_rows',n_live_tup,'bytes',total_bytes,'seq_reads_per_live_row',seq_reads_per_live_row
   ) order by seq_tup_read desc) from (select * from seq_hot limit 20)x),'[]'::jsonb),
   'fk_total',(select count(*) from fk),
   'fk_without_leading_index',(select count(*) from fk_missing),
   'fk_material_candidates',(select count(*) from fk_missing where n_live_tup>=100 or seq_tup_read>=10000),
   'fk_material_rows',coalesce((select jsonb_agg(jsonb_build_object(
      'schema',schema_name,'table',table_name,'constraint',conname,'live_rows',n_live_tup,
      'seq_tup_read',seq_tup_read,'idx_scan',idx_scan,'bytes',total_bytes
   ) order by seq_tup_read desc,n_live_tup desc) from fk_missing where n_live_tup>=100 or seq_tup_read>=10000),'[]'::jsonb),
   'unused_nonunique_indexes_ge_1mb',(select count(*) from unused_indexes),
   'unused_nonunique_rows',coalesce((select jsonb_agg(to_jsonb(x) order by index_bytes desc) from (select * from unused_indexes order by index_bytes desc limit 20)x),'[]'::jsonb)
 ),
 'payload_context',jsonb_build_object(
   'operation_rows',(select count(*) from payload_op),
   'manifest_bytes',jsonb_build_object(
      'p50',(select percentile_cont(.5) within group(order by manifest_bytes) from payload_op),
      'p95',(select percentile_cont(.95) within group(order by manifest_bytes) from payload_op),
      'max',(select max(manifest_bytes) from payload_op)
   ),
   'checkpoint_bytes',jsonb_build_object(
      'p50',(select percentile_cont(.5) within group(order by checkpoint_bytes) from payload_op),
      'p95',(select percentile_cont(.95) within group(order by checkpoint_bytes) from payload_op),
      'max',(select max(checkpoint_bytes) from payload_op)
   ),
   'step_evidence_bytes',jsonb_build_object(
      'rows',(select count(*) from payload_step),
      'p50',(select percentile_cont(.5) within group(order by evidence_bytes) from payload_step),
      'p95',(select percentile_cont(.95) within group(order by evidence_bytes) from payload_step),
      'max',(select max(evidence_bytes) from payload_step)
   ),
   'context_budget_events',(select count(*) from private.lf_context_budget_events_v2),
   'context_budget_max_tokens',(select max(estimated_tokens) from private.lf_context_budget_events_v2)
 ),
 'cache',jsonb_build_object(
   'statement_candidates',(select count(*) from cache_stats),
   'top',coalesce((select jsonb_agg(to_jsonb(x) order by total_exec_time desc) from (select * from cache_stats limit 20)x),'[]'::jsonb)
 ),
 'latency',jsonb_build_object(
   'completed_30d',(select count(*) from completed),
   'operations_30d',(select count(*) from duration_agg),
   'top_cycle_p95',coalesce((select jsonb_agg(to_jsonb(x) order by p95_s desc) from (select * from duration_agg order by p95_s desc limit 20)x),'[]'::jsonb),
   'step_rows_30d',(select count(*) from step_gaps),
   'top_step_gap_p95',coalesce((select jsonb_agg(to_jsonb(x) order by p95_gap_s desc nulls last) from (select * from gap_agg where gaps>0 order by p95_gap_s desc nulls last limit 20)x),'[]'::jsonb),
   'open_executions',(select count(*) from stuck),
   'expired_lease_open',(select count(*) from stuck where lease_expires_at is not null and lease_expires_at<now()),
   'top_open',coalesce((select jsonb_agg(to_jsonb(x) order by age_s desc) from (select * from stuck order by age_s desc limit 20)x),'[]'::jsonb)
 )
) as aud04_execution_performance;
