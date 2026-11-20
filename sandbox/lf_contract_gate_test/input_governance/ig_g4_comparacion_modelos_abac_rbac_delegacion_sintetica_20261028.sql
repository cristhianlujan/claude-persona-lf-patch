-- LF IG G4, SELECT ONLY; 20 SYNTHETIC examples. 
-- This compares configured policy variants, NOT mutually exclusive technical models.
-- The expected result is a proposed contractual oracle, NOT independently labeled LF data.
WITH scenarios(id,description,phase,target_match,context_complete,rule_active,consumer_allowed,actor_role_matches,owner_source_verified,scope_delegated,delegation_current,receipt_valid,source_policy_current,all_domains_approved,nondelegable_veto,published_scope_authorized,expected) AS MATERIALIZED (
 VALUES
('M01','Cambio autorizado y vigente','CHANGE',true,true,true,true,true,true,true,true,true,true,true,false,true,'ALLOW'),
('M02','Actor sin rol competente','CHANGE',true,true,true,true,false,true,true,true,true,true,true,false,true,'BLOCK'),
('M03','Rol correcto sin delegación de alcance','CHANGE',true,true,true,true,true,true,false,true,true,true,true,false,true,'BLOCK'),
('M04','Delegación expirada','CHANGE',true,true,true,true,true,true,true,false,true,true,true,false,true,'BLOCK'),
('M05','Recibo de otro hash/selector','CHANGE',true,true,true,true,true,true,true,true,false,true,true,false,true,'BLOCK'),
('M06','Regla multidominio con una firma faltante','CHANGE',true,true,true,true,true,true,true,true,true,true,false,false,true,'BLOCK'),
('M07','Prohibición no delegable','CHANGE',true,true,true,true,true,true,true,true,true,true,true,true,true,'BLOCK'),
('M08','Contexto requerido desconocido','CHANGE',true,false,true,true,true,true,true,true,true,true,true,false,true,'BLOCK'),
('M09','Propietario de la regla no verificado','CHANGE',true,true,true,true,true,false,true,true,true,true,true,false,true,'BLOCK'),
('M10','Política fuente caducada','CHANGE',true,true,true,true,true,true,true,true,true,false,true,false,true,'BLOCK'),
('M11','Selector no cubre destino','CHANGE',false,true,true,true,true,true,true,true,true,true,true,false,true,'BLOCK'),
('M12','Regla no vigente','CHANGE',true,true,false,true,true,true,true,true,true,true,true,false,true,'BLOCK'),
('M13','Consumidor no autorizado','CHANGE',true,true,true,false,true,true,true,true,true,true,true,false,true,'BLOCK'),
('M14','Pantalla nueva en alcance ya publicado','APPLY_EXISTING',true,true,true,true,true,true,true,true,true,true,true,false,true,'ALLOW'),
('M15','Pantalla nueva fuera de alcance publicado','APPLY_EXISTING',false,true,true,true,true,true,true,true,true,true,true,false,true,'BLOCK'),
('M16','Regla publicada pero selector no autorizado','APPLY_EXISTING',true,true,true,true,true,true,true,true,true,true,true,false,false,'BLOCK'),
('M17','Cambio válido con dos dominios conformes','CHANGE',true,true,true,true,true,true,true,true,true,true,true,false,true,'ALLOW'),
('M18','Cambio sin recibo de aprobación','CHANGE',true,true,true,true,true,true,true,true,false,true,true,false,true,'BLOCK'),
('M19','Contexto de nueva pantalla válido, dentro de alcance','APPLY_EXISTING',true,true,true,true,true,true,true,true,true,true,true,false,true,'ALLOW'),
('M20','Aplicación automática con política fuente caducada','APPLY_EXISTING',true,true,true,true,true,true,true,true,true,false,true,false,true,'BLOCK')
), common AS MATERIALIZED (
 SELECT *, (target_match AND context_complete AND rule_active AND consumer_allowed
 AND NOT nondelegable_veto) AS basic_conditions FROM scenarios
), modeled AS MATERIALIZED (
 SELECT *,
 CASE WHEN phase='APPLY_EXISTING' THEN basic_conditions AND published_scope_authorized AND source_policy_current
 ELSE basic_conditions END AS abac_minimal,
 CASE WHEN phase='APPLY_EXISTING' THEN basic_conditions AND published_scope_authorized AND source_policy_current
 ELSE basic_conditions AND actor_role_matches END AS abac_role_only,
 CASE WHEN phase='APPLY_EXISTING' THEN basic_conditions AND published_scope_authorized AND source_policy_current
 ELSE basic_conditions AND actor_role_matches AND owner_source_verified
 AND scope_delegated AND delegation_current AND receipt_valid
 AND source_policy_current AND all_domains_approved END AS abac_role_delegation
 FROM common
), decisions AS MATERIALIZED (
 SELECT id,description,phase,expected,
 CASE WHEN abac_minimal THEN 'ALLOW' ELSE 'BLOCK' END AS model_a,
 CASE WHEN abac_role_only THEN 'ALLOW' ELSE 'BLOCK' END AS model_b,
 CASE WHEN abac_role_delegation THEN 'ALLOW' ELSE 'BLOCK' END AS model_c
 FROM modeled
)
SELECT *, (model_a=expected) AS a_matches_oracle,(model_b=expected) AS b_matches_oracle,
(model_c=expected) AS c_matches_oracle FROM decisions ORDER BY id;