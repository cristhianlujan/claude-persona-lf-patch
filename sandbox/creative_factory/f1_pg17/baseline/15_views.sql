\set ON_ERROR_STOP on
CREATE VIEW saly.v_identity_current WITH (security_invoker=true) AS
 SELECT p.codigo AS project_code,
    e.code AS element_code,
    e.family,
    e.value_type,
    v.id AS version_id,
    v.version_number,
    v.channel_code,
    v.audience_code,
    v.value_json,
    v.valid_from,
    v.valid_to
   FROM saly.identity_elements e
     JOIN saly.proyecto p ON p.id = e.project_id
     JOIN saly.identity_versions v ON v.element_id = e.id
  WHERE e.status = 'ACTIVE'::text AND v.approval_status = 'APPROVED'::text AND v.valid_from <= now() AND (v.valid_to IS NULL OR now() < v.valid_to);
;
