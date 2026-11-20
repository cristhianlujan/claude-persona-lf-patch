-- SALY_DS_V1 candidate token recovery. Source immutable Git blob 551469ed451f60af43e874c4688451a210a82dc1.
-- Candidate source: PR #3715 / ref ccb1ce125f21f85a3fe163d5839e4f0fedaaa0ac, revision 1.0.0-candidate.1.
-- IMPORT ONLY. Does NOT approve candidate source values or alter existing SALY approved tokens.
-- Historical conflict is retained in candidate namespace, not promoted.
-- No LF changes; Git PR / CI / LF Migration Merge Train only.
BEGIN;

DO $preflight$
BEGIN
 IF (SELECT count(*) FROM saly.proyecto WHERE codigo='SALY-001')<>1 THEN
   RAISE EXCEPTION 'SALY_DS_CANDIDATE_PROJECT_NOT_UNIQUE'; END IF;
 IF (SELECT count(*) FROM saly.identity_elements)<>2
 OR (SELECT count(*) FROM saly.identity_versions)<>2 THEN
   RAISE EXCEPTION 'SALY_DS_CANDIDATE_IDENTITY_BASELINE_DRIFT'; END IF;
 IF (SELECT count(*) FROM saly.brand_assets WHERE approval_status='APPROVED')<>8 THEN
   RAISE EXCEPTION 'SALY_DS_CANDIDATE_APPROVED_LOGOS_DRIFT'; END IF;
 IF (SELECT count(*) FROM saly.identity_elements e
     JOIN saly.identity_versions v ON v.element_id=e.id
     WHERE e.code='color.brand.primary' AND e.status='ACTIVE'
     AND v.version_number=1 AND v.approval_status='APPROVED'
     AND v.value_json->>'value'='#00C853')<>1 THEN
   RAISE EXCEPTION 'SALY_DS_CANDIDATE_BRAND_APPROVAL_DRIFT'; END IF;
 IF (SELECT count(*) FROM saly.identity_elements e
     JOIN saly.identity_versions v ON v.element_id=e.id
     WHERE e.code='color.action.primary.bg' AND e.status='ACTIVE'
     AND v.version_number=1 AND v.approval_status='APPROVED'
     AND v.value_json->>'value'='#008200')<>1 THEN
   RAISE EXCEPTION 'SALY_DS_CANDIDATE_CTA_APPROVAL_DRIFT'; END IF;
END
$preflight$;

DO $candidate_seed$
DECLARE
  r jsonb;
  project_id_sal bigint;
  element_id_sal bigint;
  imported_count integer := 0;
  visible_count integer;
BEGIN
  SELECT p.id INTO STRICT project_id_sal FROM saly.proyecto p WHERE p.codigo='SALY-001';

  FOR r IN SELECT item.value
  FROM jsonb_array_elements($tokens$
[
 {
  "code": "candidate.saly_ds_v1.color.brand.green.600",
  "group": "color",
  "key": "brand.green.600",
  "source_path": "tokens.color.brand.green.600",
  "family": "COLOR",
  "value_type": "COLOR",
  "value": "#008200",
  "raw": {
   "value": "#008200",
   "type": "color",
   "status": "candidate",
   "usage": "Marca / acción primaria"
  },
  "conflict_note": "SOURCE_BRAND_008200_CONFLICTS_WITH_APPROVED_BRAND_00C853"
 },
 {
  "code": "candidate.saly_ds_v1.color.ink.navy.900",
  "group": "color",
  "key": "ink.navy.900",
  "source_path": "tokens.color.ink.navy.900",
  "family": "COLOR",
  "value_type": "COLOR",
  "value": "#081631",
  "raw": {
   "value": "#081631",
   "type": "color",
   "status": "candidate",
   "usage": "Texto principal y cifras"
  },
  "conflict_note": "NONE"
 },
 {
  "code": "candidate.saly_ds_v1.color.surface.white",
  "group": "color",
  "key": "surface.white",
  "source_path": "tokens.color.surface.white",
  "family": "COLOR",
  "value_type": "COLOR",
  "value": "#FFFFFF",
  "raw": {
   "value": "#FFFFFF",
   "type": "color",
   "status": "candidate",
   "usage": "Card protagonista y superficies"
  },
  "conflict_note": "NONE"
 },
 {
  "code": "candidate.saly_ds_v1.color.surface.canvas",
  "group": "color",
  "key": "surface.canvas",
  "source_path": "tokens.color.surface.canvas",
  "family": "COLOR",
  "value_type": "COLOR",
  "value": "#F5F7F7",
  "raw": {
   "value": "#F5F7F7",
   "type": "color",
   "status": "candidate",
   "usage": "Superficies secundarias"
  },
  "conflict_note": "NONE"
 },
 {
  "code": "candidate.saly_ds_v1.color.surface.mint",
  "group": "color",
  "key": "surface.mint",
  "source_path": "tokens.color.surface.mint",
  "family": "COLOR",
  "value_type": "COLOR",
  "value": "#EAF9EE",
  "raw": {
   "value": "#EAF9EE",
   "type": "color",
   "status": "candidate",
   "usage": "Fondo de Saly Plus y estados suaves"
  },
  "conflict_note": "NONE"
 },
 {
  "code": "candidate.saly_ds_v1.color.ink.gray.600",
  "group": "color",
  "key": "ink.gray.600",
  "source_path": "tokens.color.ink.gray.600",
  "family": "COLOR",
  "value_type": "COLOR",
  "value": "#5C6577",
  "raw": {
   "value": "#5C6577",
   "type": "color",
   "status": "candidate",
   "usage": "Texto secundario"
  },
  "conflict_note": "NONE"
 },
 {
  "code": "candidate.saly_ds_v1.color.accent.reward.yellow",
  "group": "color",
  "key": "accent.reward.yellow",
  "source_path": "tokens.color.accent.reward.yellow",
  "family": "COLOR",
  "value_type": "COLOR",
  "value": "#F6B400",
  "raw": {
   "value": "#F6B400",
   "type": "color",
   "status": "candidate",
   "usage": "Acento decorativo Rewards, NO texto/ícono funcional sobre blanco"
  },
  "conflict_note": "NONE"
 },
 {
  "code": "candidate.saly_ds_v1.color.accent.reward.gold.700",
  "group": "color",
  "key": "accent.reward.gold.700",
  "source_path": "tokens.color.accent.reward.gold.700",
  "family": "COLOR",
  "value_type": "COLOR",
  "value": "#9D6800",
  "raw": {
   "value": "#9D6800",
   "type": "color",
   "status": "candidate",
   "usage": "Ícono funcional Rewards contrastado"
  },
  "conflict_note": "NONE"
 },
 {
  "code": "candidate.saly_ds_v1.color.surface.reward",
  "group": "color",
  "key": "surface.reward",
  "source_path": "tokens.color.surface.reward",
  "family": "COLOR",
  "value_type": "COLOR",
  "value": "#FFF9E9",
  "raw": {
   "value": "#FFF9E9",
   "type": "color",
   "status": "candidate",
   "usage": "Fondo Rewards"
  },
  "conflict_note": "NONE"
 },
 {
  "code": "candidate.saly_ds_v1.color.accent.benefits.purple",
  "group": "color",
  "key": "accent.benefits.purple",
  "source_path": "tokens.color.accent.benefits.purple",
  "family": "COLOR",
  "value_type": "COLOR",
  "value": "#923CF3",
  "raw": {
   "value": "#923CF3",
   "type": "color",
   "status": "candidate",
   "usage": "Identidad de Beneficios"
  },
  "conflict_note": "NONE"
 },
 {
  "code": "candidate.saly_ds_v1.color.stroke.gray.200",
  "group": "color",
  "key": "stroke.gray.200",
  "source_path": "tokens.color.stroke.gray.200",
  "family": "COLOR",
  "value_type": "COLOR",
  "value": "#E4E8E8",
  "raw": {
   "value": "#E4E8E8",
   "type": "color",
   "status": "candidate",
   "usage": "Bordes y separadores"
  },
  "conflict_note": "NONE"
 },
 {
  "code": "candidate.saly_ds_v1.semantic.color.action.primary.bg",
  "group": "semantic",
  "key": "color.action.primary.bg",
  "source_path": "tokens.semantic.color.action.primary.bg",
  "family": "COLOR",
  "value_type": "JSON",
  "value": "{color.brand.green.600}",
  "raw": {
   "alias": "{color.brand.green.600}",
   "status": "CANDIDATO"
  },
  "conflict_note": "SEMANTIC_ALIAS_008200_TARGET_COLLIDES_WITH_APPROVED_CTA_TOKEN"
 },
 {
  "code": "candidate.saly_ds_v1.semantic.color.action.primary.text",
  "group": "semantic",
  "key": "color.action.primary.text",
  "source_path": "tokens.semantic.color.action.primary.text",
  "family": "COLOR",
  "value_type": "JSON",
  "value": "{color.surface.white}",
  "raw": {
   "alias": "{color.surface.white}",
   "status": "CANDIDATO"
  },
  "conflict_note": "NONE"
 },
 {
  "code": "candidate.saly_ds_v1.semantic.color.text.primary",
  "group": "semantic",
  "key": "color.text.primary",
  "source_path": "tokens.semantic.color.text.primary",
  "family": "COLOR",
  "value_type": "JSON",
  "value": "{color.ink.navy.900}",
  "raw": {
   "alias": "{color.ink.navy.900}",
   "status": "CANDIDATO"
  },
  "conflict_note": "NONE"
 },
 {
  "code": "candidate.saly_ds_v1.semantic.color.text.secondary",
  "group": "semantic",
  "key": "color.text.secondary",
  "source_path": "tokens.semantic.color.text.secondary",
  "family": "COLOR",
  "value_type": "JSON",
  "value": "{color.ink.gray.600}",
  "raw": {
   "alias": "{color.ink.gray.600}",
   "status": "CANDIDATO"
  },
  "conflict_note": "NONE"
 },
 {
  "code": "candidate.saly_ds_v1.semantic.color.surface.page",
  "group": "semantic",
  "key": "color.surface.page",
  "source_path": "tokens.semantic.color.surface.page",
  "family": "COLOR",
  "value_type": "JSON",
  "value": "{color.surface.white}",
  "raw": {
   "alias": "{color.surface.white}",
   "status": "CANDIDATO"
  },
  "conflict_note": "NONE"
 },
 {
  "code": "candidate.saly_ds_v1.semantic.color.surface.card",
  "group": "semantic",
  "key": "color.surface.card",
  "source_path": "tokens.semantic.color.surface.card",
  "family": "COLOR",
  "value_type": "JSON",
  "value": "{color.surface.white}",
  "raw": {
   "alias": "{color.surface.white}",
   "status": "CANDIDATO"
  },
  "conflict_note": "NONE"
 },
 {
  "code": "candidate.saly_ds_v1.semantic.color.surface.subtle",
  "group": "semantic",
  "key": "color.surface.subtle",
  "source_path": "tokens.semantic.color.surface.subtle",
  "family": "COLOR",
  "value_type": "JSON",
  "value": "{color.surface.canvas}",
  "raw": {
   "alias": "{color.surface.canvas}",
   "status": "CANDIDATO"
  },
  "conflict_note": "NONE"
 },
 {
  "code": "candidate.saly_ds_v1.semantic.color.border.subtle",
  "group": "semantic",
  "key": "color.border.subtle",
  "source_path": "tokens.semantic.color.border.subtle",
  "family": "COLOR",
  "value_type": "JSON",
  "value": "{color.stroke.gray.200}",
  "raw": {
   "alias": "{color.stroke.gray.200}",
   "status": "CANDIDATO"
  },
  "conflict_note": "NONE"
 },
 {
  "code": "candidate.saly_ds_v1.semantic.color.module.plus.icon",
  "group": "semantic",
  "key": "color.module.plus.icon",
  "source_path": "tokens.semantic.color.module.plus.icon",
  "family": "COLOR",
  "value_type": "JSON",
  "value": "{color.brand.green.600}",
  "raw": {
   "alias": "{color.brand.green.600}",
   "status": "CANDIDATO"
  },
  "conflict_note": "NONE"
 },
 {
  "code": "candidate.saly_ds_v1.semantic.color.module.plus.bg",
  "group": "semantic",
  "key": "color.module.plus.bg",
  "source_path": "tokens.semantic.color.module.plus.bg",
  "family": "COLOR",
  "value_type": "JSON",
  "value": "{color.surface.mint}",
  "raw": {
   "alias": "{color.surface.mint}",
   "status": "CANDIDATO"
  },
  "conflict_note": "NONE"
 },
 {
  "code": "candidate.saly_ds_v1.semantic.color.module.rewards.icon",
  "group": "semantic",
  "key": "color.module.rewards.icon",
  "source_path": "tokens.semantic.color.module.rewards.icon",
  "family": "COLOR",
  "value_type": "JSON",
  "value": "{color.accent.reward.gold.700}",
  "raw": {
   "alias": "{color.accent.reward.gold.700}",
   "status": "CANDIDATO"
  },
  "conflict_note": "NONE"
 },
 {
  "code": "candidate.saly_ds_v1.semantic.color.module.rewards.bg",
  "group": "semantic",
  "key": "color.module.rewards.bg",
  "source_path": "tokens.semantic.color.module.rewards.bg",
  "family": "COLOR",
  "value_type": "JSON",
  "value": "{color.surface.reward}",
  "raw": {
   "alias": "{color.surface.reward}",
   "status": "CANDIDATO"
  },
  "conflict_note": "NONE"
 },
 {
  "code": "candidate.saly_ds_v1.semantic.color.module.benefits.icon",
  "group": "semantic",
  "key": "color.module.benefits.icon",
  "source_path": "tokens.semantic.color.module.benefits.icon",
  "family": "COLOR",
  "value_type": "JSON",
  "value": "{color.accent.benefits.purple}",
  "raw": {
   "alias": "{color.accent.benefits.purple}",
   "status": "CANDIDATO"
  },
  "conflict_note": "NONE"
 },
 {
  "code": "candidate.saly_ds_v1.typography.font.family.base",
  "group": "typography",
  "key": "font.family.base",
  "source_path": "tokens.typography.font.family.base",
  "family": "TYPOGRAPHY",
  "value_type": "JSON",
  "value": "Inter, system-ui, sans-serif",
  "raw": {
   "value": "Inter, system-ui, sans-serif",
   "status": "CANDIDATO"
  },
  "conflict_note": "NONE"
 },
 {
  "code": "candidate.saly_ds_v1.typography.font.amount.hero",
  "group": "typography",
  "key": "font.amount.hero",
  "source_path": "tokens.typography.font.amount.hero",
  "family": "TYPOGRAPHY",
  "value_type": "JSON",
  "value": {
   "size_px": 48,
   "line_height_px": 56,
   "weight": 700
  },
  "raw": {
   "size_px": 48,
   "line_height_px": 56,
   "weight": 700,
   "status": "CANDIDATO"
  },
  "conflict_note": "NONE"
 },
 {
  "code": "candidate.saly_ds_v1.typography.font.heading.card",
  "group": "typography",
  "key": "font.heading.card",
  "source_path": "tokens.typography.font.heading.card",
  "family": "TYPOGRAPHY",
  "value_type": "JSON",
  "value": {
   "size_px": 20,
   "line_height_px": 28,
   "weight": 600
  },
  "raw": {
   "size_px": 20,
   "line_height_px": 28,
   "weight": 600,
   "status": "CANDIDATO"
  },
  "conflict_note": "NONE"
 },
 {
  "code": "candidate.saly_ds_v1.typography.font.heading.section",
  "group": "typography",
  "key": "font.heading.section",
  "source_path": "tokens.typography.font.heading.section",
  "family": "TYPOGRAPHY",
  "value_type": "JSON",
  "value": {
   "size_px": 22,
   "line_height_px": 30,
   "weight": 700
  },
  "raw": {
   "size_px": 22,
   "line_height_px": 30,
   "weight": 700,
   "status": "CANDIDATO"
  },
  "conflict_note": "NONE"
 },
 {
  "code": "candidate.saly_ds_v1.typography.font.body.default",
  "group": "typography",
  "key": "font.body.default",
  "source_path": "tokens.typography.font.body.default",
  "family": "TYPOGRAPHY",
  "value_type": "JSON",
  "value": {
   "size_px": 16,
   "line_height_px": 24,
   "weight": 400
  },
  "raw": {
   "size_px": 16,
   "line_height_px": 24,
   "weight": 400,
   "status": "CANDIDATO"
  },
  "conflict_note": "NONE"
 },
 {
  "code": "candidate.saly_ds_v1.typography.font.body.secondary",
  "group": "typography",
  "key": "font.body.secondary",
  "source_path": "tokens.typography.font.body.secondary",
  "family": "TYPOGRAPHY",
  "value_type": "JSON",
  "value": {
   "size_px": 14,
   "line_height_px": 20,
   "weight": 400
  },
  "raw": {
   "size_px": 14,
   "line_height_px": 20,
   "weight": 400,
   "status": "CANDIDATO"
  },
  "conflict_note": "NONE"
 },
 {
  "code": "candidate.saly_ds_v1.typography.font.caption",
  "group": "typography",
  "key": "font.caption",
  "source_path": "tokens.typography.font.caption",
  "family": "TYPOGRAPHY",
  "value_type": "JSON",
  "value": {
   "size_px": 12,
   "line_height_px": 16,
   "weight": 400
  },
  "raw": {
   "size_px": 12,
   "line_height_px": 16,
   "weight": 400,
   "status": "CANDIDATO"
  },
  "conflict_note": "NONE"
 },
 {
  "code": "candidate.saly_ds_v1.typography.font.button.primary",
  "group": "typography",
  "key": "font.button.primary",
  "source_path": "tokens.typography.font.button.primary",
  "family": "TYPOGRAPHY",
  "value_type": "JSON",
  "value": {
   "size_px": 16,
   "line_height_px": 24,
   "weight": 600
  },
  "raw": {
   "size_px": 16,
   "line_height_px": 24,
   "weight": 600,
   "status": "CANDIDATO"
  },
  "conflict_note": "NONE"
 },
 {
  "code": "candidate.saly_ds_v1.spacing.space.4",
  "group": "spacing",
  "key": "space.4",
  "source_path": "tokens.spacing.space.4",
  "family": "SPACING",
  "value_type": "NUMBER",
  "value": 4,
  "raw": {
   "px": 4,
   "status": "CANDIDATO"
  },
  "conflict_note": "NONE"
 },
 {
  "code": "candidate.saly_ds_v1.spacing.space.8",
  "group": "spacing",
  "key": "space.8",
  "source_path": "tokens.spacing.space.8",
  "family": "SPACING",
  "value_type": "NUMBER",
  "value": 8,
  "raw": {
   "px": 8,
   "status": "CANDIDATO"
  },
  "conflict_note": "NONE"
 },
 {
  "code": "candidate.saly_ds_v1.spacing.space.12",
  "group": "spacing",
  "key": "space.12",
  "source_path": "tokens.spacing.space.12",
  "family": "SPACING",
  "value_type": "NUMBER",
  "value": 12,
  "raw": {
   "px": 12,
   "status": "CANDIDATO"
  },
  "conflict_note": "NONE"
 },
 {
  "code": "candidate.saly_ds_v1.spacing.space.16",
  "group": "spacing",
  "key": "space.16",
  "source_path": "tokens.spacing.space.16",
  "family": "SPACING",
  "value_type": "NUMBER",
  "value": 16,
  "raw": {
   "px": 16,
   "status": "CANDIDATO"
  },
  "conflict_note": "NONE"
 },
 {
  "code": "candidate.saly_ds_v1.spacing.space.24",
  "group": "spacing",
  "key": "space.24",
  "source_path": "tokens.spacing.space.24",
  "family": "SPACING",
  "value_type": "NUMBER",
  "value": 24,
  "raw": {
   "px": 24,
   "status": "CANDIDATO"
  },
  "conflict_note": "NONE"
 },
 {
  "code": "candidate.saly_ds_v1.spacing.space.32",
  "group": "spacing",
  "key": "space.32",
  "source_path": "tokens.spacing.space.32",
  "family": "SPACING",
  "value_type": "NUMBER",
  "value": 32,
  "raw": {
   "px": 32,
   "status": "CANDIDATO"
  },
  "conflict_note": "NONE"
 },
 {
  "code": "candidate.saly_ds_v1.spacing.space.48",
  "group": "spacing",
  "key": "space.48",
  "source_path": "tokens.spacing.space.48",
  "family": "SPACING",
  "value_type": "NUMBER",
  "value": 48,
  "raw": {
   "px": 48,
   "status": "CANDIDATO"
  },
  "conflict_note": "NONE"
 },
 {
  "code": "candidate.saly_ds_v1.radius.radius.card.hero",
  "group": "radius",
  "key": "radius.card.hero",
  "source_path": "tokens.radius.radius.card.hero",
  "family": "LAYOUT",
  "value_type": "NUMBER",
  "value": 24,
  "raw": {
   "px": 24,
   "status": "CANDIDATO"
  },
  "conflict_note": "NONE"
 },
 {
  "code": "candidate.saly_ds_v1.radius.radius.card.secondary",
  "group": "radius",
  "key": "radius.card.secondary",
  "source_path": "tokens.radius.radius.card.secondary",
  "family": "LAYOUT",
  "value_type": "NUMBER",
  "value": 16,
  "raw": {
   "px": 16,
   "status": "CANDIDATO"
  },
  "conflict_note": "NONE"
 },
 {
  "code": "candidate.saly_ds_v1.radius.radius.button.primary",
  "group": "radius",
  "key": "radius.button.primary",
  "source_path": "tokens.radius.radius.button.primary",
  "family": "LAYOUT",
  "value_type": "NUMBER",
  "value": 14,
  "raw": {
   "px": 14,
   "status": "CANDIDATO"
  },
  "conflict_note": "NONE"
 },
 {
  "code": "candidate.saly_ds_v1.radius.radius.pill",
  "group": "radius",
  "key": "radius.pill",
  "source_path": "tokens.radius.radius.pill",
  "family": "LAYOUT",
  "value_type": "NUMBER",
  "value": 999,
  "raw": {
   "px": 999,
   "status": "CANDIDATO"
  },
  "conflict_note": "NONE"
 },
 {
  "code": "candidate.saly_ds_v1.accessibility.touch_target_min_px",
  "group": "accessibility",
  "key": "touch_target_min_px",
  "source_path": "tokens.accessibility.touch_target_min_px",
  "family": "RULE",
  "value_type": "JSON",
  "value": 44,
  "raw": 44,
  "conflict_note": "NONE"
 },
 {
  "code": "candidate.saly_ds_v1.accessibility.supports_font_scaling",
  "group": "accessibility",
  "key": "supports_font_scaling",
  "source_path": "tokens.accessibility.supports_font_scaling",
  "family": "RULE",
  "value_type": "JSON",
  "value": true,
  "raw": true,
  "conflict_note": "NONE"
 },
 {
  "code": "candidate.saly_ds_v1.accessibility.use_color_as_sole_signal",
  "group": "accessibility",
  "key": "use_color_as_sole_signal",
  "source_path": "tokens.accessibility.use_color_as_sole_signal",
  "family": "RULE",
  "value_type": "JSON",
  "value": false,
  "raw": false,
  "conflict_note": "NONE"
 }
]
$tokens$::jsonb) AS item(value)
  LOOP
    IF length(r->>'code')>128 OR r->>'group' NOT IN
      ('color','semantic','typography','spacing','radius','accessibility') THEN
      RAISE EXCEPTION 'SALY_DS_INVALID_CANDIDATE_SOURCE_ROW';
    END IF;

    INSERT INTO saly.identity_elements
      (project_id,code,family,value_type,name,description,
       is_required,is_protected,status,decision_id,metadata)
    VALUES
      (project_id_sal, r->>'code', r->>'family', r->>'value_type',
       r->>'key', 'Imported candidate from SALY_DS_V1; not effective or approved',
       false,false,'DRAFT',NULL,
       jsonb_build_object(
          'source_artifact','SALY_DS_V1',
          'source_revision','1.0.0-candidate.1',
          'source_git_blob','551469ed451f60af43e874c4688451a210a82dc1',
          'source_git_commit','ccb1ce125f21f85a3fe163d5839e4f0fedaaa0ac',
          'source_pr_number',3715,
          'source_path',r->>'source_path',
          'source_group',r->>'group',
          'original_key',r->>'key',
          'original_payload',r->'raw',
          'conflict_note',r->>'conflict_note',
          'import_status','CANDIDATE_ONLY',
          'canonical_binding','NOT_MAPPED_TO_APPROVED_KEYS'
        ))
    RETURNING id INTO element_id_sal;

    INSERT INTO saly.identity_versions
      (element_id,version_number,channel_code,audience_code,value_json,
       approval_status,valid_from,valid_to,decision_id,approval_reference,change_reason,metadata)
    VALUES
      (element_id_sal,1,'GLOBAL','ALL',
       jsonb_build_object('value',r->'value'),
       'CANDIDATE',NULL,NULL,NULL,NULL,
       'Recovered candidate source, no explicit token approval',
       jsonb_build_object(
         'source_git_blob','551469ed451f60af43e874c4688451a210a82dc1',
         'source_path',r->>'source_path',
         'source_payload',r->'raw',
         'raw_value_type',jsonb_typeof(r->'value'),
         'conflict_note',r->>'conflict_note',
         'not_effective',true,
         'approval_required_for_activation',true
       ));
    imported_count:=imported_count+1;
  END LOOP;

  IF imported_count<>46 THEN
    RAISE EXCEPTION 'SALY_DS_CANDIDATE_ROWS_NOT_46:%',imported_count; END IF;

  IF (SELECT count(*) FROM saly.identity_elements)<>48
  OR (SELECT count(*) FROM saly.identity_versions)<>48 THEN
    RAISE EXCEPTION 'SALY_DS_CANDIDATE_TOTAL_COUNTS_FAILED'; END IF;

  IF (SELECT count(*) FROM saly.identity_elements
      WHERE code LIKE 'candidate.saly_ds_v1.%'
        AND status='DRAFT' AND NOT is_required AND NOT is_protected)<>46 THEN
    RAISE EXCEPTION 'SALY_DS_CANDIDATE_ELEMENT_STATUS_INVALID'; END IF;

  IF (SELECT count(*) FROM saly.identity_versions v
      JOIN saly.identity_elements e ON e.id=v.element_id
      WHERE e.code LIKE 'candidate.saly_ds_v1.%'
        AND v.approval_status='CANDIDATE'
        AND v.version_number=1
        AND v.channel_code='GLOBAL'
        AND v.audience_code='ALL'
        AND v.valid_from IS NULL AND v.valid_to IS NULL
        AND v.approval_reference IS NULL)<>46 THEN
    RAISE EXCEPTION 'SALY_DS_CANDIDATE_VERSION_STATUS_INVALID'; END IF;

  IF (SELECT count(*) FROM saly.identity_elements e
      JOIN saly.identity_versions v ON e.id=v.element_id
      WHERE e.code LIKE 'candidate.saly_ds_v1.%'
        AND (e.status='ACTIVE' OR v.approval_status='APPROVED'))<>0 THEN
    RAISE EXCEPTION 'SALY_DS_CANDIDATE_IMPROPER_ACTIVATION'; END IF;

  SELECT count(*) INTO visible_count FROM saly.v_identity_current
  WHERE project_code='SALY-001';
  IF visible_count<>2 THEN
    RAISE EXCEPTION 'SALY_DS_CANDIDATE_LEAKED_TO_CURRENT_VIEW:%',visible_count; END IF;

  SELECT count(*) INTO visible_count FROM
    saly.resolve_identity('SALY-001','APP','B2C',transaction_timestamp());
  IF visible_count<>2 THEN
    RAISE EXCEPTION 'SALY_DS_CANDIDATE_LEAKED_TO_RESOLVER:%',visible_count; END IF;

  IF (SELECT count(*) FROM saly.identity_elements e
      JOIN saly.identity_versions v ON v.element_id=e.id
      WHERE e.code IN ('color.brand.primary','color.action.primary.bg')
       AND e.status='ACTIVE' AND v.approval_status='APPROVED'
       AND v.version_number=1 AND
       ((e.code='color.brand.primary' AND v.value_json->>'value'='#00C853')
       OR (e.code='color.action.primary.bg' AND v.value_json->>'value'='#008200')))<>2
  THEN RAISE EXCEPTION 'SALY_DS_CANDIDATE_EXISTING_APPROVAL_CHANGED'; END IF;
  IF (SELECT count(*) FROM saly.brand_assets WHERE approval_status='APPROVED')<>8 THEN
    RAISE EXCEPTION 'SALY_DS_CANDIDATE_LOGO_COUNT_CHANGED'; END IF;

  IF (SELECT count(*) FROM saly.identity_elements e
      WHERE e.code LIKE 'candidate.saly_ds_v1.%'
        AND e.metadata->>'source_git_blob'='551469ed451f60af43e874c4688451a210a82dc1')<>46 THEN
    RAISE EXCEPTION 'SALY_DS_CANDIDATE_PROVENANCE_MISSING'; END IF;
END
$candidate_seed$;
COMMIT;
