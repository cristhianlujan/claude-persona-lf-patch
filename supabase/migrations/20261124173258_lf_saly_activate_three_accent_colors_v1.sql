-- Explicit owner approval 2026-11-24 10:31 America/Lima; only three SALY accents.
-- Preserve original candidate versions referenced by sealed historical creative context 1.
BEGIN;
DO $activate$
DECLARE n integer;
BEGIN
 PERFORM id FROM saly.identity_elements WHERE project_id=2 AND id IN(12,13,15) ORDER BY id FOR UPDATE;
 IF (SELECT count(*) FROM saly.identity_elements e JOIN saly.identity_versions v ON v.element_id=e.id
 WHERE e.project_id=2 AND e.status='DRAFT' AND e.family='COLOR' AND e.value_type='COLOR'
 AND v.version_number=1 AND v.approval_status='CANDIDATE' AND v.valid_from IS NULL AND v.valid_to IS NULL
 AND v.channel_code='GLOBAL' AND v.audience_code='ALL'
 AND (e.id,e.code,v.id,v.value_json->>'value') IN
 ((12,'candidate.saly_ds_v1.color.accent.reward.yellow',16,'#F6B400'),
 (13,'candidate.saly_ds_v1.color.accent.reward.gold.700',17,'#9D6800'),
 (15,'candidate.saly_ds_v1.color.accent.benefits.purple',19,'#923CF3')))<>3
 OR (SELECT count(*) FROM saly.identity_versions WHERE element_id IN(12,13,15))<>3
 THEN RAISE EXCEPTION 'SALY_ACCENT_ACTIVATION_BASELINE_DRIFT'; END IF;
 INSERT INTO saly.identity_versions(element_id,version_number,channel_code,audience_code,value_json,approval_status,valid_from,valid_to,approval_reference,change_reason,metadata)
 SELECT v.element_id,2,v.channel_code,v.audience_code,v.value_json,'APPROVED',transaction_timestamp(),NULL,
 'OWNER_CHAT_APPROVAL:2026-11-24T10:31-05:00:SALY_THREE_ACCENTS',
 'Owner approved activation of exact existing accent color; original candidate version preserved.',
 (v.metadata - 'not_effective' - 'approval_required_for_activation') || jsonb_build_object('approval_authority','OWNER_EXPLICIT_CHAT_CONFIRMATION','approval_date_local','2026-11-24','derived_from_version_id',v.id,'valid_from_meaning','REGISTRY_ACTIVATION_NOT_RETROACTIVE_DESIGN_APPROVAL')
 FROM saly.identity_versions v WHERE v.id IN(16,17,19);
 GET DIAGNOSTICS n=ROW_COUNT;
 IF n<>3 THEN RAISE EXCEPTION 'SALY_ACCENT_VERSION_COUNT_MISMATCH'; END IF;
 UPDATE saly.identity_elements SET status='ACTIVE',updated_at=transaction_timestamp()
 WHERE project_id=2 AND id IN(12,13,15) AND status='DRAFT';
 GET DIAGNOSTICS n=ROW_COUNT;
 IF n<>3 THEN RAISE EXCEPTION 'SALY_ACCENT_ELEMENT_COUNT_MISMATCH'; END IF;
 IF (SELECT count(*) FROM saly.v_identity_current WHERE project_code='SALY-001' AND version_number=2 AND
 (element_code,value_json->>'value') IN
 (('candidate.saly_ds_v1.color.accent.reward.yellow','#F6B400'),
 ('candidate.saly_ds_v1.color.accent.reward.gold.700','#9D6800'),
 ('candidate.saly_ds_v1.color.accent.benefits.purple','#923CF3')))<>3
 THEN RAISE EXCEPTION 'SALY_ACCENT_CURRENT_VIEW_MISMATCH'; END IF;
END
$activate$;
COMMIT;
