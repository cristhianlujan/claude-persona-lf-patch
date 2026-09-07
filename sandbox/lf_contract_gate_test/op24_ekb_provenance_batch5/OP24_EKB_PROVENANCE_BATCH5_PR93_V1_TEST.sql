\set ON_ERROR_STOP on

begin;
\ir OP24_EKB_PROVENANCE_BATCH5_PR93_V1.sql

do $assert$
declare
  v_total integer;
  v_bound integer;
  v_bad_pr integer;
  v_bad_hash integer;
begin
  select count(*),
         count(*) filter (where source_ref='github://cristhianlujan/claude-persona-lf-patch/pull/93'),
         count(*) filter (where regexp_replace(coalesce(pr,''),'[^0-9]','','g')<>'93'),
         count(*) filter (where encode(extensions.digest(convert_to(evidencia,'UTF8'),'sha256'),'hex') not in (
           '401babb93a55a890b57532091aa8b112a4bab5f3788b35d16275481fa0e8153a',
           'd2dfe2e7106598566523fe592b0f368c1a64999d16926a7d1d6bb235794e1ed1',
           'b9ef3af870753748e4a508b6f589b34c65fca5f37e228690dd67548943b74b06',
           '99dc38988f6bc0f10bf6a5613eff6a8aba5e0dfb6ba1d41d96e3f7881b6ee35f',
           'db840a85f4af3cbd186ace6c580ae1aeb27693e31e30381faf6eb29abef652c5',
           '248d26970f870a5157c407bad47e8671395c2925eadf0e3492735a94868817a3',
           '689dfed6dcff5072797d4aedf8f909a7b5df3952bc852723a5a7da9a856631e7',
           'e5c4e7460d2b992c12d7b09bb7e2694fe7c4826c6d1e26bfe8cb9bfc76e31dcb',
           'a8d2cb698a4925110d839fcfdfae1fc431a8d847561040e74ee258c9806d0004',
           'f7a07b59a36da5e8a1bf0abd7b5eeb88f6a60e763d7d6495a03732b457c1cd0f'
         ))
    into v_total,v_bound,v_bad_pr,v_bad_hash
  from transversal.error_knowledge
  where codigo in ('DEV-001','OBS-001','RTE-001','RTE-002','RTE-004','SEC-002','SEC-006','SQL-006','SRC-003','TOOL-001');

  if v_total<>10 or v_bound<>10 or v_bad_pr<>0 or v_bad_hash<>0 then
    raise exception 'BATCH5_ASSERT_FAIL total=% bound=% bad_pr=% bad_hash=%',v_total,v_bound,v_bad_pr,v_bad_hash;
  end if;
end
$assert$;

rollback;

do $post$
declare
  v_nonnull integer;
begin
  select count(*) into v_nonnull
  from transversal.error_knowledge
  where codigo in ('DEV-001','OBS-001','RTE-001','RTE-002','RTE-004','SEC-002','SEC-006','SQL-006','SRC-003','TOOL-001')
    and source_ref is not null;
  if v_nonnull<>0 then
    raise exception 'BATCH5_ROLLBACK_RESIDUE:%',v_nonnull;
  end if;
end
$post$;
