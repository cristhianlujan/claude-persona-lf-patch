-- Owner explicit approval 2026-11-24 13:56 America/Lima: entire candidate design system.
-- Preserve historical versions and exact value_json.
BEGIN;
DO $activate$
DECLARE n integer;
BEGIN
 INSERT INTO saly.identity_versions(element_id,version_number,channel_code,audience_code,value_json,approval_status,valid_from,valid_to,approval_reference,change_reason,metadata)
 SELECT v.element_id,2,v.channel_code,v.audience_code,v.value_json,'APPROVED',transaction_timestamp(),NULL,
 'OWNER_CHAT_APPROVAL:2026-11-24T13:56-05:00:SALY_DESIGN_SYSTEM',
 'Owner approved existing candidate design system; original version preserved.',
 (v.metadata - 'not_effective' - 'approval_required_for_activation') || jsonb_build_object('approval_authority','OWNER_EXPLICIT_CHAT_CONFIRMATION','approval_date_local','2026-11-24','derived_from_version_id',v.id,'valid_from_meaning','REGISTRY_ACTIVATION_NOT_RETROACTIVE_DESIGN_APPROVAL')
 FROM saly.identity_versions v JOIN saly.identity_elements e ON e.id=v.element_id
 WHERE e.project_id=2 AND e.id IN(6,7,8,9,10,11,14,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,53,54,55,56,57,58,59) AND e.status='DRAFT' AND v.version_number=1 AND v.approval_status='CANDIDATE';
 GET DIAGNOSTICS n=ROW_COUNT;
 IF n<>50 THEN RAISE EXCEPTION 'SALY_DS_VERSION_COUNT_MISMATCH: %',n; END IF;
 UPDATE saly.identity_elements SET status='ACTIVE',updated_at=transaction_timestamp()
 WHERE project_id=2 AND id IN(6,7,8,9,10,11,14,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,53,54,55,56,57,58,59) AND status='DRAFT';
 GET DIAGNOSTICS n=ROW_COUNT;
 IF n<>50 THEN RAISE EXCEPTION 'SALY_DS_ELEMENT_COUNT_MISMATCH: %',n; END IF;
 IF (SELECT count(*) FROM saly.v_identity_current WHERE project_code='SALY-001' AND element_code IN (SELECT code FROM saly.identity_elements WHERE id IN(6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,53,54,55,56,57,58,59)))<>53
 THEN RAISE EXCEPTION 'SALY_DS_CURRENT_VIEW_MISMATCH'; END IF;
 IF EXISTS(SELECT 1 FROM (VALUES ('candidate.saly_ds_v1.semantic.color.action.primary.bg','candidate.saly_ds_v1.color.brand.green.600'),
('candidate.saly_ds_v1.semantic.color.action.primary.text','candidate.saly_ds_v1.color.surface.white'),
('candidate.saly_ds_v1.semantic.color.text.primary','candidate.saly_ds_v1.color.ink.navy.900'),
('candidate.saly_ds_v1.semantic.color.text.secondary','candidate.saly_ds_v1.color.ink.gray.600'),
('candidate.saly_ds_v1.semantic.color.surface.page','candidate.saly_ds_v1.color.surface.white'),
('candidate.saly_ds_v1.semantic.color.surface.card','candidate.saly_ds_v1.color.surface.white'),
('candidate.saly_ds_v1.semantic.color.surface.subtle','candidate.saly_ds_v1.color.surface.canvas'),
('candidate.saly_ds_v1.semantic.color.border.subtle','candidate.saly_ds_v1.color.stroke.gray.200'),
('candidate.saly_ds_v1.semantic.color.module.plus.icon','candidate.saly_ds_v1.color.brand.green.600'),
('candidate.saly_ds_v1.semantic.color.module.plus.bg','candidate.saly_ds_v1.color.surface.mint'),
('candidate.saly_ds_v1.semantic.color.module.rewards.icon','candidate.saly_ds_v1.color.accent.reward.gold.700'),
('candidate.saly_ds_v1.semantic.color.module.rewards.bg','candidate.saly_ds_v1.color.surface.reward'),
('candidate.saly_ds_v1.semantic.color.module.benefits.icon','candidate.saly_ds_v1.color.accent.benefits.purple'),
('candidate.saly_home_v3.semantic.color.navigation.active','color.action.primary.bg'),
('candidate.saly_home_v3.semantic.color.navigation.inactive','candidate.saly_ds_v1.color.ink.gray.600'),
('candidate.saly_home_v3.semantic.color.navigation.background','candidate.saly_ds_v1.color.surface.white'),
('candidate.saly_home_v3.semantic.color.module.benefits.bg','candidate.saly_home_v3.color.surface.benefits')) a(alias_code,target_code)
 WHERE NOT EXISTS(SELECT 1 FROM saly.v_identity_current v WHERE v.project_code='SALY-001' AND v.element_code=a.target_code AND v.value_json->>'value' ~ '^#[0-9A-Fa-f]{6}$')
 OR NOT EXISTS(SELECT 1 FROM saly.v_identity_current v WHERE v.project_code='SALY-001' AND v.element_code=a.alias_code AND v.value_json->>'value'='{'||regexp_replace(a.target_code,'^candidate\.saly_(ds_v1|home_v3)\.','')||'}'))
 THEN RAISE EXCEPTION 'SALY_DS_ALIAS_NOT_RESOLVED'; END IF;
END
$activate$;
COMMIT;
