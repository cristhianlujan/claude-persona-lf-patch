-- Exact function sources read from Supabase; synthetic PG17 tests only.
-- No credentials and no production table data.
-- LIVE programacion.fn_v09_canonical_jsonb_text md5=ccfd6892fdaf0ec45ad55e638dfb25c6
CREATE OR REPLACE FUNCTION programacion.fn_v09_canonical_jsonb_text(j jsonb)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE STRICT
 SET search_path TO 'pg_catalog', 'programacion'
AS $function$
declare
  r text := '';
  kv record;
  elem record;
  first boolean := true;
  t text;
begin
  t := jsonb_typeof(j);
  if t = 'object' then
    r := '{';
    for kv in select key, value from jsonb_each(j) order by key collate "C" loop
      if not first then r := r || ','; end if;
      first := false;
      r := r || to_json(kv.key)::text || ':' || programacion.fn_v09_canonical_jsonb_text(kv.value);
    end loop;
    return r || '}';
  elsif t = 'array' then
    r := '[';
    first := true;
    for elem in select value from jsonb_array_elements(j) with ordinality as a(value, ord) order by ord loop
      if not first then r := r || ','; end if;
      first := false;
      r := r || programacion.fn_v09_canonical_jsonb_text(elem.value);
    end loop;
    return r || ']';
  else
    return j::text;
  end if;
end;
$function$;

-- LIVE programacion.fn_v09_sha256_jsonb md5=5864925d00feff49120a560b3b7b004d
CREATE OR REPLACE FUNCTION programacion.fn_v09_sha256_jsonb(j jsonb)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE STRICT SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
  select encode(
    extensions.digest(
      convert_to(programacion.fn_v09_canonical_jsonb_text($1), 'UTF8'),
      'sha256'
    ),
    'hex'
  );
$function$;

-- LIVE programacion.fn_guard_provenance_receipt_insert md5=32da02afebd3f8ff4281b52312f0aaec
CREATE OR REPLACE FUNCTION programacion.fn_guard_provenance_receipt_insert()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'programacion'
AS $function$
declare
  v_token text;
  v_token_sha text;
  v_allowed text[];
  v_head text;
  v_payload jsonb;
  v_digest text;
begin
  v_token:=current_setting('programacion.provenance_channel_token',true);
  if length(coalesce(v_token,''))<32 then
    raise exception 'verified provenance receipt requires external channel token';
  end if;

  v_token_sha:=encode(extensions.digest(convert_to(v_token,'UTF8'),'sha256'),'hex');

  select allowed_kinds into v_allowed
  from programacion.provenance_channels
  where channel_code=new.issuer_channel
    and secret_sha256=v_token_sha;

  if v_allowed is null then
    raise exception 'verified provenance channel/token mismatch';
  end if;

  if not (new.receipt_kind=any(v_allowed)) then
    raise exception 'channel % is not authorized for receipt kind %',
      new.issuer_channel,new.receipt_kind;
  end if;

  if length(btrim(coalesce(new.issuer_identity,'')))=0
     or length(btrim(coalesce(new.verification_ref,'')))=0
     or length(btrim(coalesce(new.subject_type,'')))=0
     or length(btrim(coalesce(new.subject_ref,'')))=0 then
    raise exception 'verified provenance receipt identity/reference fields are required';
  end if;

  if new.execution_id is not null then
    select head_sha into v_head
    from programacion.ejecuciones
    where id=new.execution_id;

    if v_head is null then
      raise exception 'provenance receipt execution % not found',new.execution_id;
    end if;

    if new.head_sha is distinct from v_head then
      raise exception 'provenance receipt HEAD mismatch';
    end if;

    if new.payload->>'execution_id' is distinct from new.execution_id::text then
      raise exception 'provenance receipt payload execution mismatch';
    end if;
  end if;

  if new.payload->>'head_sha' is distinct from new.head_sha
     or new.payload->>'subject_type' is distinct from new.subject_type
     or new.payload->>'subject_ref' is distinct from new.subject_ref
     or new.payload->>'subject_sha256' is distinct from new.subject_sha256 then
    raise exception 'provenance receipt payload envelope mismatch';
  end if;

  if new.receipt_kind='AUDIT_VERDICT' then
    if new.payload->>'verdict' not in ('PASS','FAIL','BLOCKED')
       or new.payload->'independent' is distinct from 'true'::jsonb
       or length(btrim(coalesce(new.payload->>'auditor_identity','')))=0 then
      raise exception 'AUDIT_VERDICT receipt requires independent auditor verdict';
    end if;

  elsif new.receipt_kind='HUMAN_DECISION' then
    if new.payload->>'decision' not in ('APPROVE','REJECT')
       or length(btrim(coalesce(new.payload->>'actor_identity','')))=0
       or length(btrim(coalesce(new.payload->>'approval_ref','')))=0 then
      raise exception 'HUMAN_DECISION receipt requires actor/approval provenance';
    end if;

  elsif new.receipt_kind='HUMAN_ROUTING_DECISION' then
    if new.subject_type is distinct from 'HUMAN_DECISION_ROUTING_REQUEST'
       or new.payload->>'request_id' is distinct from new.subject_ref
       or new.payload->>'request_sha256' is distinct from new.subject_sha256
       or coalesce(new.payload->>'request_sha256','') !~ '^[0-9a-f]{64}$'
       or coalesce(new.payload->>'currentness_sha256','') !~ '^[0-9a-f]{64}$'
       or length(btrim(coalesce(new.payload->>'action_code','')))=0
       or length(btrim(coalesce(new.payload->>'actor_identity','')))=0
       or length(btrim(coalesce(new.payload->>'approval_ref','')))=0
       or length(btrim(coalesce(new.payload->>'reviewer_role','')))=0
       or length(btrim(coalesce(new.payload->>'authority_ref','')))=0
       or jsonb_typeof(new.payload->'decision_payload') is distinct from 'object' then
      raise exception 'HUMAN_ROUTING_DECISION receipt contract invalid';
    end if;

  elsif new.receipt_kind='PLAYWRIGHT_RUN' then
    if new.payload->>'status' not in ('PASS','FAIL','BLOCKED','NOT_APPLICABLE')
       or length(btrim(coalesce(new.payload->>'run_ref','')))=0 then
      raise exception 'PLAYWRIGHT_RUN receipt requires externally verified run_ref/status';
    end if;

  elsif new.receipt_kind='EVIDENCE_VERIFICATION' then
    if new.payload->>'verification_status' not in ('VERIFIED','REJECTED')
       or length(btrim(coalesce(new.payload->>'verifier_identity','')))=0 then
      raise exception 'EVIDENCE_VERIFICATION receipt requires verifier provenance';
    end if;
  end if;

  v_payload:=jsonb_build_object(
    'schema_version',1,
    'receipt_kind',new.receipt_kind,
    'execution_id',new.execution_id,
    'head_sha',new.head_sha,
    'subject_type',new.subject_type,
    'subject_ref',new.subject_ref,
    'subject_sha256',new.subject_sha256,
    'issuer_channel',new.issuer_channel,
    'issuer_identity',new.issuer_identity,
    'verification_ref',new.verification_ref,
    'payload',new.payload
  );

  v_digest:=programacion.fn_v09_sha256_jsonb(v_payload);

  if new.receipt_sha256 is distinct from v_digest then
    raise exception 'verified provenance receipt digest mismatch';
  end if;

  return new;
end
$function$;

-- LIVE public.lf_rule_promotion_apply_v1 md5=d7fe763c999db6f6259b6b1e2bd69644
CREATE OR REPLACE FUNCTION public.lf_rule_promotion_apply_v1(p_promotion_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
declare p record;
begin
 select * into p from public.lf_rule_promotion_v1 where promotion_id=p_promotion_id for update;
 if not found then return jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_NOT_FOUND'); end if;
 if p.status<>'APPROVED' then return jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_NOT_APPROVED','estado',p.status); end if;
 if public.lf_asset_snapshot_sha_v1('REGLA',p.rule_code) is distinct from p.request_snapshot_sha256 then
  update public.lf_rule_promotion_v1 set status='STALE' where promotion_id=p_promotion_id;
  return jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_STALE'); end if;
 update lf_ops.reglas set estado='VIGENTE' where codigo=p.rule_code and estado='CANDIDATO';
 update public.lf_rule_promotion_v1 set status='APPLIED', applied_at=now() where promotion_id=p_promotion_id;
 return jsonb_build_object('status','APPLIED','rule_code',p.rule_code);
end $function$;

-- LIVE public.lf_rule_promotion_decide_v1 md5=16e45f40dad5cecc215a2f978be47728
CREATE OR REPLACE FUNCTION public.lf_rule_promotion_decide_v1(p_promotion_id text, p_decision text, p_decided_by text, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
declare p record;
begin
 if p_decided_by is null or p_decided_by !~ '^HUMAN:.+' then return jsonb_build_object('status','BLOCKED','blocking_code','APPROVER_MUST_BE_HUMAN'); end if;
 if p_decision not in ('APPROVE','REJECT') then return jsonb_build_object('status','BLOCKED','blocking_code','DECISION_INVALID'); end if;
 select * into p from public.lf_rule_promotion_v1 where promotion_id=p_promotion_id for update;
 if not found then return jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_NOT_FOUND'); end if;
 if p.status<>'PENDING' then return jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_NOT_PENDING','estado',p.status); end if;
 if p_decision='APPROVE' and public.lf_asset_snapshot_sha_v1('REGLA',p.rule_code) is distinct from p.request_snapshot_sha256 then
  update public.lf_rule_promotion_v1 set status='STALE' where promotion_id=p_promotion_id;
  return jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_STALE'); end if;
 update public.lf_rule_promotion_v1 set status=case p_decision when 'APPROVE' then 'APPROVED' else 'REJECTED' end, decided_by=p_decided_by, decided_at=now(), reason=coalesce(reason,'')||' | '||coalesce(p_note,'') where promotion_id=p_promotion_id;
 return jsonb_build_object('status',case p_decision when 'APPROVE' then 'APPROVED' else 'REJECTED' end,'promotion_id',p_promotion_id);
end $function$;

-- LIVE public.lf_rule_promotion_guard_v1 md5=ee782e4bd0128c80ee13881899c0d74e
CREATE OR REPLACE FUNCTION public.lf_rule_promotion_guard_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
begin
 if NEW.estado='VIGENTE' and OLD.estado is distinct from 'VIGENTE' then
  if not exists(select 1 from public.lf_rule_promotion_v1 p where p.rule_code=OLD.codigo and p.status='APPROVED' and p.request_snapshot_sha256=public.lf_asset_snapshot_sha_v1('REGLA',OLD.codigo)) then
   raise exception 'LF_RULE_PROMOTION_REQUIRED:%',OLD.codigo; end if;
 end if;
 return NEW;
end $function$;
