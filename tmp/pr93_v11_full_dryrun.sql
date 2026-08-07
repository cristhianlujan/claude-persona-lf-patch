-- PR93 V11 full dry-run. Caller wraps this file in BEGIN/ROLLBACK.
set local statement_timeout='15min';
set local lock_timeout='10s';
grant usage,create on schema private to lf_governance_owner_v3;
grant usage,create on schema private to lf_writer_verifier_v7;

do $dry$
declare
 r record; c text; body text; st int; begin_n int; commit_n int;
 b bigint; z bigint; lastn bigint; actual text;
 wc int:=0; gc int:=0; w int; g int; applied int:=0;
begin
 if exists(
   select 1 from supabase_migrations.schema_migrations sm
   where sm.version in ('20260801175950','20260801175955','20260801180000','20260801180005','20260801180100','20260801180150','20260801180200','20260801180300','20260801180305','20260801180310','20260801180315','20260801180320','20260801180400','20260801180500','20260801180510','20260801180520','20260801180530')
 ) then raise exception 'target versions already present'; end if;

 for r in
   select * from (values
(1,'20260801175950','20260801175950_prepare_v7_object_owners.sql','484323bfe892cb1824320130203fd86d8aed69bf',984),
(2,'20260801175955','20260801175955_prepare_writer_verifier_schema_context.sql','5a4586911376274efab625b54a5cd16ab6648798',561),
(3,'20260801180000','20260801180000_writer_hmac_nonce_v7.sql','07f7258d43444f3d871257e9e7095edd0b4a41c7',23385),
(4,'20260801180005','20260801180005_cleanup_writer_verifier_schema_context.sql','470739dac867faa82c25dce5ad17febfbcea422b',288),
(5,'20260801180100','20260801180100_quarantine_compensating_evidence_v7.sql','38297c53f9670e13920b95e0d9b251f5cd2bf26d',19163),
(6,'20260801180150','20260801180150_trusted_v7_readback_grants.sql','04e90e404358098d97e78f447519d15a1e1b8742',520),
(7,'20260801180200','20260801180200_governance_role_and_rls_v7.sql','48ed99596b40022b4a8e9af6bfcd3a14a68562e1',6887),
(8,'20260801180300','20260801180300_static_audit_corrections_v7.sql','d23d0cd14459dacfeced2457ebebf35ebe098c04',15683),
(9,'20260801180305','20260801180305_prepare_idempotency_owner_context.sql','1ab7a093a4e1934f5319d0d7584a9aa7f8d3fa1c',399),
(10,'20260801180310','20260801180310_v7_idempotency_guards.sql','f0461362480449a9039987c60bba6865c67d13fe',15553),
(11,'20260801180315','20260801180315_v7_row_integrity_guards.sql','ace19fefd8b656b82a9b86639ef7abb567a04e58',4861),
(12,'20260801180320','20260801180320_cleanup_idempotency_owner_context.sql','d785677981f2030c7167d1c9a4df97f47310a2bb',287),
(13,'20260801180400','20260801180400_writer_key_rotation_v7.sql','3357696625dc05c951a937b1a05f1350e46fd320',23903),
(14,'20260801180500','20260801180500_writer_canonicalization_rls_v7.sql','d41297db3d3bed95ba4f0a6286399dbee268570b',29448),
(15,'20260801180510','20260801180510_writer_full_payload_binding_v7.sql','a52faeedf7b44e00da512dd6c6b34aacd3976a95',6397),
(16,'20260801180520','20260801180520_writer_scope_nonce_binding_realign_v7.sql','a1ae795920180014b4fa84fa4010b7fc7f5f7f64',9758),
(17,'20260801180530','20260801180530_writer_evidence_runtime_hardening_v7.sql','d38230b6bd2e899ccbafb28dc15adb881f1677cb',13867)
   ) x(seq,version,filename,sha,bytes) order by seq
 loop
   select h.status,h.content into st,c
   from extensions.http_get(
     ('https://raw.githubusercontent.com/cristhianlujan/claude-persona-lf-patch/fd6a1b28d05135b8708439fd90c1c4f4e6bc9e45/supabase/migrations/'||r.filename)::varchar
   ) h;
   if st<>200 or octet_length(convert_to(c,'UTF8'))<>r.bytes then
     raise exception 'download/size failed %',r.filename;
   end if;
   actual:=encode(extensions.digest(
     convert_to('blob '||r.bytes::text,'UTF8')||decode('00','hex')||convert_to(c,'UTF8'),
     'sha1'),'hex');
   if actual<>r.sha then raise exception 'hash failed %',r.filename; end if;

   with l as (
     select line,ord
     from unnest(string_to_array(replace(c,E'\r\n',E'\n'),E'\n'))
     with ordinality x(line,ord)
   )
   select
     count(*) filter(where lower(btrim(line))='begin;'),
     count(*) filter(where lower(btrim(line))='commit;'),
     min(ord) filter(where lower(btrim(line))='begin;'),
     max(ord) filter(where lower(btrim(line))='commit;'),
     max(ord) filter(where btrim(line)<>'')
   into begin_n,commit_n,b,z,lastn
   from l;

   if begin_n<>1 or commit_n<>1 or b is null or z is null or z<>lastn then
     raise exception 'wrapper failed % begin=% commit=%',r.filename,begin_n,commit_n;
   end if;

   select string_agg(line,E'\n' order by ord) into body
   from unnest(string_to_array(replace(c,E'\r\n',E'\n'),E'\n'))
   with ordinality x(line,ord)
   where ord not in(b,z);

   if r.filename='20260801180005_cleanup_writer_verifier_schema_context.sql' then
     body:='-- deferred';
   end if;

   w:=(length(body)-length(replace(body,
     'revoke lf_writer_verifier_v7 from postgres granted by postgres;','')))
     /length('revoke lf_writer_verifier_v7 from postgres granted by postgres;');
   g:=(length(body)-length(replace(body,
     'revoke lf_governance_owner_v3 from postgres granted by postgres;','')))
     /length('revoke lf_governance_owner_v3 from postgres granted by postgres;');

   body:=replace(body,
     'revoke lf_writer_verifier_v7 from postgres granted by postgres;',
     '-- deferred writer membership revoke');
   body:=replace(body,
     'revoke lf_governance_owner_v3 from postgres granted by postgres;',
     '-- deferred governance membership revoke');
   wc:=wc+w; gc:=gc+g;

   execute body;
   insert into supabase_migrations.schema_migrations(
     version,statements,name,created_by,idempotency_key
   ) values(
     r.version,array[body],r.filename,'pr93_v11_dry_run','dry:'||r.sha
   );
   applied:=applied+1;
 end loop;

 if applied<>17 or wc<>5 or gc<>7 then
   raise exception 'counts failed applied=% writer=% governance=%',applied,wc,gc;
 end if;

 revoke create on schema public from lf_governance_owner_v3;
 revoke create on schema private from lf_governance_owner_v3;
 revoke create on schema private from lf_writer_verifier_v7;
 revoke lf_governance_owner_v3 from postgres granted by postgres;
 revoke lf_writer_verifier_v7 from postgres granted by postgres;

 if not has_schema_privilege('lf_governance_owner_v3','private','USAGE')
    or not has_schema_privilege('lf_writer_verifier_v7','private','USAGE') then
   raise exception 'runtime owner USAGE missing';
 end if;
 if to_regclass('private.lf_reconciliation_writer_nonces_v7') is null
    or to_regclass('private.lf_github_reconciliation_quarantine_v7') is null
    or to_regclass('private.lf_writer_hmac_keys_v7') is null then
   raise exception 'critical table missing';
 end if;
 if pg_get_userbyid((select relowner from pg_class where oid='private.lf_reconciliation_writer_nonces_v7'::regclass))<>'lf_writer_verifier_v7' then
   raise exception 'nonce owner wrong';
 end if;
 if pg_get_userbyid((select relowner from pg_class where oid='private.lf_github_reconciliation_quarantine_v7'::regclass))<>'lf_governance_owner_v3' then
   raise exception 'quarantine owner wrong';
 end if;
 if pg_get_userbyid((select relowner from pg_class where oid='private.lf_writer_hmac_keys_v7'::regclass))<>'postgres' then
   raise exception 'key owner wrong';
 end if;
end
$dry$;

select 'V11_DRY_RUN_17_OF_17_PASS' as status;
