-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / M3.2 / PAULO-042
-- Six thin IG resolver primitives with one common signature.
-- Scope: reference, graph, policy, subject, threat, provider.
-- No new semantic engine; each primitive delegates to current canonical authority.

begin;

create or replace function programacion.fn_input_resolver_reference_v1(
  p_pantalla_id integer,
  p_family_code text,
  p_version_id bigint default 19
)
returns jsonb
language sql
stable
as $fn$
  select programacion.fn_input_governance_field_reference_probe_v1(
    p_pantalla_id,
    p_family_code,
    p_version_id
  );
$fn$;

create or replace function programacion.fn_input_resolver_graph_v1(
  p_pantalla_id integer,
  p_family_code text,
  p_version_id bigint default 19
)
returns jsonb
language sql
stable
as $fn$
  select programacion.fn_input_screen_canonical_graph(
    p_pantalla_id,
    p_version_id
  );
$fn$;

create or replace function programacion.fn_input_resolver_policy_v1(
  p_pantalla_id integer,
  p_family_code text,
  p_version_id bigint default 19
)
returns jsonb
language plpgsql
stable
as $fn$
declare
  v_policy jsonb;
begin
  select c.especificacion->'families'->p_family_code
    into v_policy
  from programacion.contratos c
  where c.version_id = p_version_id
    and c.contrato_codigo = 'INPUT_FAMILY_POLICY_REGISTRY';

  if v_policy is null then
    raise exception 'INPUT_FAMILY_POLICY_NOT_FOUND:%@%', p_family_code, p_version_id;
  end if;

  return v_policy;
end;
$fn$;

create or replace function programacion.fn_input_resolver_subject_v1(
  p_pantalla_id integer,
  p_family_code text,
  p_version_id bigint default 19
)
returns jsonb
language sql
stable
as $fn$
  select programacion.fn_input_subject_depth_expected_v510(
    p_pantalla_id,
    p_family_code
  );
$fn$;

create or replace function programacion.fn_input_resolver_threat_v1(
  p_pantalla_id integer,
  p_family_code text,
  p_version_id bigint default 19
)
returns jsonb
language sql
stable
as $fn$
  select programacion.fn_input_security_threat_expected_v510(
    p_pantalla_id
  );
$fn$;

create or replace function programacion.fn_input_resolver_provider_v1(
  p_pantalla_id integer,
  p_family_code text,
  p_version_id bigint default 19
)
returns jsonb
language sql
stable
as $fn$
  select programacion.fn_input_security_capability_profile(
    p_pantalla_id
  );
$fn$;

comment on function programacion.fn_input_resolver_reference_v1(integer,text,bigint) is
'M3.2 REFERENCE primitive. Thin adapter over canonical field-reference probe; common IG resolver signature.';

comment on function programacion.fn_input_resolver_graph_v1(integer,text,bigint) is
'M3.2 GRAPH primitive. Thin adapter over canonical screen graph; common IG resolver signature.';

comment on function programacion.fn_input_resolver_policy_v1(integer,text,bigint) is
'M3.2 POLICY primitive. Reads INPUT_FAMILY_POLICY_REGISTRY authority fail-closed; common IG resolver signature.';

comment on function programacion.fn_input_resolver_subject_v1(integer,text,bigint) is
'M3.2 SUBJECT primitive. Thin adapter over subject-depth authority; common IG resolver signature.';

comment on function programacion.fn_input_resolver_threat_v1(integer,text,bigint) is
'M3.2 THREAT primitive. Thin adapter over threat-expected authority; common IG resolver signature.';

comment on function programacion.fn_input_resolver_provider_v1(integer,text,bigint) is
'M3.2 PROVIDER primitive. Thin adapter over security capability profile; common IG resolver signature.';

-- Compile-time/readback contract for this migration only.
do $verify$
declare
  v_missing integer;
begin
  select count(*)
    into v_missing
  from (values
    ('programacion.fn_input_resolver_reference_v1(integer,text,bigint)'::regprocedure),
    ('programacion.fn_input_resolver_graph_v1(integer,text,bigint)'::regprocedure),
    ('programacion.fn_input_resolver_policy_v1(integer,text,bigint)'::regprocedure),
    ('programacion.fn_input_resolver_subject_v1(integer,text,bigint)'::regprocedure),
    ('programacion.fn_input_resolver_threat_v1(integer,text,bigint)'::regprocedure),
    ('programacion.fn_input_resolver_provider_v1(integer,text,bigint)'::regprocedure)
  ) v(fn)
  where v.fn is null;

  if v_missing <> 0 then
    raise exception 'M3_2_PRIMITIVES_READBACK_FAILED:%', v_missing;
  end if;
end;
$verify$;

commit;
