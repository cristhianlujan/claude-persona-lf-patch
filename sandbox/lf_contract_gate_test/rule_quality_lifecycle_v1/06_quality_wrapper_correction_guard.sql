-- LOTE 14: SANDBOX CORRECTION + ACTIVATION TRIGGER. NO FROZEN GATE EDIT.
SET search_path=rule_quality_l13,public;

CREATE FUNCTION quality_propose_correction(p_project text,p_original text,p_successor text,
 p_new_definition text,p_evidence jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=rule_quality_l13,pg_temp AS $fn$
DECLARE v_actor text;v_old rules%ROWTYPE;
BEGIN
 v_actor:=trusted_actor_role(p_project);
 IF p_successor IS NULL OR btrim(p_successor)='' OR p_successor=p_original THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_QUALITY_EXPLICIT_SUCCESSOR_REQUIRED';
 END IF;
 IF jsonb_typeof(p_evidence) IS DISTINCT FROM 'object'
   OR nullif(btrim(p_evidence->>'source_ref'),'') IS NULL
   OR nullif(btrim(p_evidence->>'rationale'),'') IS NULL THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_QUALITY_CORRECTION_EVIDENCE_REQUIRED';
 END IF;
 SELECT * INTO v_old FROM rules WHERE project_code=p_project
  AND rule_code=p_original AND state='VIGENTE';
 IF NOT FOUND THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_QUALITY_ORIGINAL_NOT_VIGENTE';
 END IF;
 INSERT INTO rules(project_code,rule_code,family_code,category_raw,entity_code,
                   definition_text,config,state)
 VALUES(p_project,p_successor,v_old.family_code,v_old.category_raw,
        v_old.entity_code,p_new_definition,v_old.config,'EN_REVISION');
 INSERT INTO correction_requests(project_code,original_rule_code,successor_rule_code,
                                 owner_role,evidence)
 VALUES(p_project,p_original,p_successor,v_actor,p_evidence);
 RETURN jsonb_build_object('status','EN_REVISION','original_rule_code',p_original,
    'successor_rule_code',p_successor,'project_code',p_project,'owner_role',v_actor);
END $fn$;

-- One trigger implementation for LF and SALY source columns, different TG_ARGV adapters.
-- This stops direct frozen apply from reaching VIGENTE without pre-staged metadata/ticket.
CREATE FUNCTION source_quality_activation_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=rule_quality_l13,pg_temp AS $fn$
DECLARE v_project text:=TG_ARGV[0];v_code text;v_category text;v_description text;
        v_is_active text;v_record rules%ROWTYPE;v_ticket activation_tickets%ROWTYPE;
BEGIN
 v_is_active:=to_jsonb(NEW)->>TG_ARGV[4];
 IF v_is_active IS DISTINCT FROM TG_ARGV[5] THEN RETURN NEW; END IF;
 IF TG_OP='UPDATE'
    AND (to_jsonb(OLD)->>TG_ARGV[4]) IS NOT DISTINCT FROM v_is_active THEN
    RETURN NEW;
 END IF;
 v_code:=to_jsonb(NEW)->>TG_ARGV[1];
 v_category:=to_jsonb(NEW)->>TG_ARGV[2];
 v_description:=to_jsonb(NEW)->>TG_ARGV[3];
 SELECT * INTO v_record FROM rules WHERE project_code=v_project AND rule_code=v_code;
 IF NOT FOUND OR v_record.family_code IS NULL OR v_record.reviewed_at IS NULL
    OR v_record.next_review_at IS NULL OR v_record.next_review_at<=clock_timestamp()
    OR v_record.category_raw IS DISTINCT FROM v_category
    OR v_record.definition_text IS DISTINCT FROM v_description THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_QUALITY_ACTIVE_METADATA_MISSING';
 END IF;
 SELECT * INTO v_ticket FROM activation_tickets
  WHERE project_code=v_project AND rule_code=v_code AND status='ARMED';
 IF NOT FOUND OR v_ticket.actor_role<>session_user THEN
   RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_QUALITY_NO_ACTIVATION_TICKET';
 END IF;
 RETURN NEW;
END $fn$;

CREATE TRIGGER trg_l14_lf_quality_activate
 BEFORE INSERT OR UPDATE OF estado ON lf_ops.reglas FOR EACH ROW
 EXECUTE FUNCTION source_quality_activation_guard(
  'lf','codigo','categoria','descripcion','estado','VIGENTE');

CREATE TRIGGER trg_l14_saly_quality_activate
 BEFORE INSERT OR UPDATE OF vigente ON saly_source_synthetic FOR EACH ROW
 EXECUTE FUNCTION source_quality_activation_guard(
  'saly','codigo','categoria','regla','vigente','true');

-- Immutable content of already-active rules. Corrections must be separately proposed
-- via explicit version/successor, never silently UPDATE a VIGENTE row in place.
CREATE FUNCTION source_quality_no_active_in_place_edit() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=rule_quality_l13,pg_temp AS $fn$
DECLARE v_old jsonb:=to_jsonb(OLD);v_new jsonb:=to_jsonb(NEW);
BEGIN
 IF v_old->>TG_ARGV[0] = TG_ARGV[1]
    AND ((v_old->>TG_ARGV[2]) IS DISTINCT FROM (v_new->>TG_ARGV[2])
         OR (v_old->TG_ARGV[3]) IS DISTINCT FROM (v_new->TG_ARGV[3])) THEN
   RAISE EXCEPTION USING ERRCODE='23514',
     MESSAGE='BLOCK_QUALITY_ACTIVE_RULE_IN_PLACE_MUTATION';
 END IF;
 RETURN NEW;
END $fn$;
CREATE TRIGGER trg_l14_lf_no_inplace_active_edit
 BEFORE UPDATE OF descripcion,valor_config ON lf_ops.reglas FOR EACH ROW
 EXECUTE FUNCTION source_quality_no_active_in_place_edit('estado','VIGENTE','descripcion','valor_config');
CREATE TRIGGER trg_l14_saly_no_inplace_active_edit
 BEFORE UPDATE OF regla,valor_config ON saly_source_synthetic FOR EACH ROW
 EXECUTE FUNCTION source_quality_no_active_in_place_edit('vigente','true','regla','valor_config');
