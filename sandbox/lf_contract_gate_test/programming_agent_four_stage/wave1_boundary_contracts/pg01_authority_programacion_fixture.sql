-- Disposable PostgreSQL only. Mirrors (read-only inspection of Supabase, 29-oct-2026) the existing
-- programacion authority roles and copies programacion.fn_assert_external_authority_session verbatim.
DO $r$ DECLARE r text; BEGIN
 FOREACH r IN ARRAY ARRAY['programacion_builder','programacion_auditor','programacion_verifier','programacion_human_authority','programacion_promoter'] LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname=r) THEN EXECUTE format('CREATE ROLE %I NOLOGIN',r); END IF; END LOOP;
 FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role','authenticator'] LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname=r) THEN EXECUTE format('CREATE ROLE %I NOLOGIN',r); END IF; END LOOP; END $r$;
CREATE SCHEMA IF NOT EXISTS programacion;
GRANT USAGE ON SCHEMA programacion TO programacion_auditor, programacion_verifier;
CREATE OR REPLACE FUNCTION programacion.fn_assert_external_authority_session(p_allowed_roles text[])
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'programacion'
AS $function$
declare
  v_login boolean;
  v_super boolean;
  v_createdb boolean;
  v_createrole boolean;
  v_inherit boolean;
  v_replication boolean;
  v_bypassrls boolean;
begin
  if not (current_user = any(p_allowed_roles)) then
    raise exception 'external authority role required; current_user=% allowed=%', current_user, p_allowed_roles;
  end if;

  if session_user in ('postgres','authenticator','service_role','programacion_builder') then
    raise exception 'shared/control-plane session principal % is forbidden for external authority', session_user;
  end if;

  if session_user = current_user then
    raise exception 'authority group role % is NOLOGIN; a distinct external login session is required', current_user;
  end if;

  select rolcanlogin,rolsuper,rolcreatedb,rolcreaterole,rolinherit,rolreplication,rolbypassrls
    into v_login,v_super,v_createdb,v_createrole,v_inherit,v_replication,v_bypassrls
    from pg_roles where rolname=session_user;

  if coalesce(v_login,false)=false
     or coalesce(v_super,false)
     or coalesce(v_createdb,false)
     or coalesce(v_createrole,false)
     or coalesce(v_inherit,true)
     or coalesce(v_replication,false)
     or coalesce(v_bypassrls,false) then
    raise exception 'authority login % is not least-privilege LOGIN/NOINHERIT/NOSUPERUSER/NOCREATEDB/NOCREATEROLE/NOREPLICATION/NOBYPASSRLS', session_user;
  end if;

  if not exists(
    select 1
      from pg_auth_members m
      join pg_roles granted on granted.oid=m.roleid
      join pg_roles member on member.oid=m.member
     where granted.rolname=current_user
       and member.rolname=session_user
       and m.set_option=true
       and m.inherit_option=false
       and m.admin_option=false
  ) then
    raise exception 'authority login % lacks direct least-privilege SET membership to %', session_user,current_user;
  end if;

  if exists(
    select 1
      from pg_auth_members m
      join pg_roles granted on granted.oid=m.roleid
      join pg_roles member on member.oid=m.member
     where member.rolname=session_user
       and granted.rolname in ('programacion_builder','programacion_auditor','programacion_verifier','programacion_human_authority','programacion_promoter')
       and granted.rolname<>current_user
       and (m.set_option or m.inherit_option or m.admin_option)
  ) then
    raise exception 'authority login % has cross-authority membership beyond %',session_user,current_user;
  end if;
end;
$function$;
GRANT EXECUTE ON FUNCTION programacion.fn_assert_external_authority_session(text[]) TO programacion_auditor, programacion_verifier;
-- Synthetic external logins (sandbox only). Real logins are provisioned by the owner outside the producer.
CREATE ROLE lf_t_verifier_login LOGIN NOINHERIT; GRANT programacion_verifier TO lf_t_verifier_login WITH INHERIT FALSE, SET TRUE;
CREATE ROLE lf_t_auditor_login LOGIN NOINHERIT;  GRANT programacion_auditor TO lf_t_auditor_login WITH INHERIT FALSE, SET TRUE;
CREATE ROLE lf_t_inherit_login LOGIN INHERIT;    GRANT programacion_auditor TO lf_t_inherit_login WITH INHERIT FALSE, SET TRUE;
CREATE ROLE lf_t_dual_login LOGIN NOINHERIT;     GRANT programacion_auditor TO lf_t_dual_login WITH INHERIT FALSE, SET TRUE;
                                                 GRANT programacion_verifier TO lf_t_dual_login WITH INHERIT FALSE, SET TRUE;
CREATE ROLE lf_t_nologin NOLOGIN NOINHERIT;      GRANT programacion_auditor TO lf_t_nologin WITH INHERIT FALSE, SET TRUE;
CREATE ROLE lf_t_auditor2_login LOGIN NOINHERIT; GRANT programacion_auditor TO lf_t_auditor2_login WITH INHERIT FALSE, SET TRUE;
CREATE ROLE lf_t_verifier2_login LOGIN NOINHERIT; GRANT programacion_verifier TO lf_t_verifier2_login WITH INHERIT FALSE, SET TRUE;
GRANT service_role TO authenticator;
-- Helpers: run SQL as <login> with SET ROLE <authority> (needs superuser harness; impossible for service_role).
CREATE FUNCTION pg_temp.as_authority(p_login text, p_role text, p_sql text) RETURNS text LANGUAGE plpgsql AS $q$
DECLARE res text:='OK'; BEGIN
 EXECUTE format('SET SESSION AUTHORIZATION %I',p_login); EXECUTE format('SET ROLE %I',p_role);
 BEGIN EXECUTE p_sql; EXCEPTION WHEN OTHERS THEN res:='ERROR:'||SQLERRM; END;
 RESET ROLE; RESET SESSION AUTHORIZATION; RETURN res;
EXCEPTION WHEN OTHERS THEN RESET ROLE; RESET SESSION AUTHORIZATION; RETURN 'ERROR:'||SQLERRM; END $q$;
CREATE FUNCTION pg_temp.as_role(p_role text, p_sql text) RETURNS text LANGUAGE plpgsql AS $q$
DECLARE res text:='OK'; BEGIN
 EXECUTE format('SET ROLE %I',p_role);
 BEGIN EXECUTE p_sql; EXCEPTION WHEN OTHERS THEN res:='ERROR:'||SQLERRM; END;
 RESET ROLE; RETURN res; END $q$;
-- service_role exactly as PostgREST presents it: session_user=authenticator (non-superuser), SET ROLE service_role.
CREATE FUNCTION pg_temp.as_service(p_sql text) RETURNS text LANGUAGE plpgsql AS $q$
DECLARE res text:='OK'; BEGIN
 EXECUTE 'SET SESSION AUTHORIZATION authenticator'; EXECUTE 'SET ROLE service_role';
 BEGIN EXECUTE p_sql; EXCEPTION WHEN OTHERS THEN res:='ERROR:'||SQLERRM; END;
 RESET ROLE; RESET SESSION AUTHORIZATION; RETURN res;
EXCEPTION WHEN OTHERS THEN RESET ROLE; RESET SESSION AUTHORIZATION; RETURN 'ERROR:'||SQLERRM; END $q$;
