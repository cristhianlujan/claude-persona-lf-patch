-- LF #3779 | Scope-authorized ownership metadata for 578 EXISTING rules.
-- Important: the official lf_asset_snapshot_sha_v1 hashes to_jsonb(lf_ops.reglas)
-- (minus timestamps). Do not add owner columns to, or UPDATE, lf_ops.reglas.
-- Attribution of ChatGPT is user-declared, NOT audit proof of historical actor.
-- No rule state, business approval, policy or Router/Profile change.
BEGIN;

DO $lf_rule_owner_guard$
DECLARE
  n integer; unique_codes integer; source_md5 text;
BEGIN
  IF to_regclass('lf_ops.reglas_owner_metadata_v1') IS NOT NULL
  OR to_regclass('lf_ops.v_reglas_owner_metadata_v1') IS NOT NULL THEN
    RAISE EXCEPTION 'BLOCK_LF_RULE_OWNER_METADATA_ALREADY_EXISTS';
  END IF;
  SELECT count(*),count(DISTINCT codigo),
    md5(string_agg(id::text||':'||codigo,E'\n' ORDER BY id))
    INTO n,unique_codes,source_md5
  FROM lf_ops.reglas;
  IF n<>578 OR unique_codes<>578
  OR source_md5<>'c758e1215c5fe5a11d34d42456a09664' THEN
    RAISE EXCEPTION 'BLOCK_LF_RULE_OWNER_PREIMAGE_DRIFT count=%,unique=%,md5=%',
      n,unique_codes,source_md5;
  END IF;
END $lf_rule_owner_guard$;

CREATE TABLE lf_ops.reglas_owner_metadata_v1 (
 regla_id integer PRIMARY KEY
   REFERENCES lf_ops.reglas(id) ON DELETE CASCADE,
 owner_name text NOT NULL
   CHECK (length(btrim(owner_name))>0),
 declared_creator_agent text NOT NULL
   CHECK (length(btrim(declared_creator_agent))>0),
 declaration_basis text NOT NULL
   CHECK (declaration_basis IN
    ('USER_DECLARATION_2026_11_10','LATER_GOVERNED_REASSIGNMENT')),
 assigned_at timestamptz NOT NULL DEFAULT transaction_timestamp()
);

COMMENT ON TABLE lf_ops.reglas_owner_metadata_v1 IS
 'Administrative ownership/declared AI author only, based on the user scope '
 'decision of 2026-11-10. NOT a business approval or historical creator audit. '
 'Separated from lf_ops.reglas to preserve SHA256 of all rules and screens.';
COMMENT ON COLUMN lf_ops.reglas_owner_metadata_v1.declared_creator_agent IS
 'ChatGPT, as declared by the user for the existing 578 rules; does not '
 'overwrite or attest lf_ops.reglas.created_by.';

INSERT INTO lf_ops.reglas_owner_metadata_v1 (
 regla_id,owner_name,declared_creator_agent,declaration_basis
)
SELECT r.id,'SUPER_ADMIN','ChatGPT','USER_DECLARATION_2026_11_10'
FROM lf_ops.reglas r
ORDER BY r.id;

DO $lf_rule_owner_readback$
DECLARE n integer; wrong integer; uncovered integer;
BEGIN
 SELECT count(*),
   count(*) FILTER(WHERE owner_name IS DISTINCT FROM 'SUPER_ADMIN'
     OR declared_creator_agent IS DISTINCT FROM 'ChatGPT'
     OR declaration_basis IS DISTINCT FROM 'USER_DECLARATION_2026_11_10')
   INTO n,wrong
 FROM lf_ops.reglas_owner_metadata_v1;
 SELECT count(*) INTO uncovered FROM lf_ops.reglas r
 LEFT JOIN lf_ops.reglas_owner_metadata_v1 om ON om.regla_id=r.id
 WHERE om.regla_id IS NULL;
 IF n<>578 OR wrong<>0 OR uncovered<>0 THEN
   RAISE EXCEPTION 'BLOCK_LF_RULE_OWNER_BACKFILL_MISMATCH total=%,wrong=%,uncovered=%',
      n,wrong,uncovered;
 END IF;
END $lf_rule_owner_readback$;

CREATE VIEW lf_ops.v_reglas_owner_metadata_v1
 WITH (security_invoker=true) AS
SELECT
 r.id AS regla_id,r.codigo AS regla_codigo,r.estado AS estado_regla,
 r.categoria,r.es_transversal,r.origen,
 r.created_by AS historical_created_by,
 om.owner_name,om.declared_creator_agent,om.declaration_basis,
 om.assigned_at,
 false::boolean AS business_decision_approval_inferred
FROM lf_ops.reglas r
JOIN lf_ops.reglas_owner_metadata_v1 om ON om.regla_id=r.id;

-- Metadata is read-only to runtime consumers; any future reassignment must
-- use its own authorized/governed operation. Neither creator nor approval
-- is inferred from legacy created_by.
REVOKE ALL ON TABLE lf_ops.reglas_owner_metadata_v1
 FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON TABLE lf_ops.v_reglas_owner_metadata_v1
 FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT ON TABLE lf_ops.reglas_owner_metadata_v1 TO service_role;
GRANT SELECT ON TABLE lf_ops.v_reglas_owner_metadata_v1 TO service_role;

COMMIT;
