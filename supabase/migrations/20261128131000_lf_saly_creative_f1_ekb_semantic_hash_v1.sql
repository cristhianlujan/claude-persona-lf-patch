-- SALY F1: learning readback for semantic hash domain and existing workflow-entrypoint incident.
BEGIN;

INSERT INTO transversal.error_knowledge
(codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,frecuencia,lote_origen,estado,evidencia,lifecycle_phase,consumer_role,root_cause_family,detectability,source_context,source_ref)
VALUES
(
 'SALY-F1-SEMANTIC-HASH-DOMAIN-20261128-001',
 'TESTING',
 'Hash semantic_qa original_request_sha256 no equivale al hash de un literal aislado',
 'En el item 27 el hash requerido 78160d6438c2908d469e9ece838b0a14b57eb317b1215cfb702e507e7bbb1f40 corresponde a la serializacion jsonb de original_messages: pedido original + enmienda del dueño. El hash del literal actual y el del literal original son dominios distintos.',
 'Riesgo de comparar hashes SHA-256 sintacticamente validos que tienen preimagenes y dominios semanticos diferentes.',
 'SEMANTIC_QA_HASH_DOMAIN_CONFUSION',
 'Antes de persistir semantic_qa, reconstruir la preimagen exacta que consume creative_assert_dual_qa_l3c: (semantic_qa.original_messages)::text en jsonb; comparar ese digest con original_request_sha256. No sustituirlo por literal_request, original_literal_request ni scope_json.',
 'PR #4847 HEAD 3585885c1af5323ac9d0e1267563e64f51cb16bb: PG17 exact migration rollback emitio PR3_ITEM27_POSITIVE|PASS y PR3_ITEM27_NEGATIVE|PASS; el negativo bloqueo LF_SEM_ORIGINAL_MESSAGES_HASH_DRIFT.',
 'HIGH',
 1,
 'SALY_CREATIVE_F1_20261128',
 'ACTIVO',
 'Read-only producción: hash original_messages=78160d6438c2908d469e9ece838b0a14b57eb317b1215cfb702e507e7bbb1f40; hash literal actual=d6c44a55b386ff5fff4863b24466a74ec833ee9743367e80191bec862c7245f7; hash literal original=0182dbc314eec19e0a30890ad105920fabc9b04a8c76285a3ef03493d8db0715.',
 'DESIGN',
 ARRAY['CLAUDE_NATIVE','PROGRAMADOR'],
 'R2_NO_VE',
 'PROCESS_DEPENDENT',
 'SALY Fabrica Digital F1',
 'https://github.com/cristhianlujan/claude-persona-lf-patch/pull/4847'
)
ON CONFLICT (codigo) DO NOTHING;

INSERT INTO transversal.error_knowledge
(codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,frecuencia,lote_origen,estado,evidencia,lifecycle_phase,consumer_role,root_cause_family,detectability,source_context,source_ref)
VALUES
(
 'SALY-F1-EKB-NULL-EVIDENCE-APPEND-20261128-001',
 'GOVERNANCE',
 'Append de evidencia EKB con columna NULL puede aparentar actualización sin persistir texto',
 'Concatenar evidencia || texto conserva NULL cuando la evidencia previa es NULL; el UPDATE puede afectar la fila pero el readback textual sigue ausente.',
 'Se asumió que evidencia histórica era siempre no nula antes de concatenar.',
 'EKB_NULL_TEXT_CONCAT',
 'Antes de anexar texto a campos EKB nullable usar coalesce(evidencia,'''') || texto y hacer readback del marcador exacto dentro de la misma transacción.',
 'PR #4850: run 46151830451 fallo con SALY_F1_WORKFLOW_EKB_READBACK_MISSING; read-only confirmó PE10_C6_UNAUTHORIZED_GITHUB_WORKFLOW_ENTRYPOINT_V1 con evidencia=NULL y APPLIED=false. Run 46152059045 detectó que el QA buscaba ese marcador en evidencia aunque estaba registrado en validacion; el readback debe consultar el campo exacto donde se persiste la evidencia.',
 'HIGH',
 1,
 'SALY_CREATIVE_F1_20261128',
 'ACTIVO',
 'Run 46151830451: EXACT_APPLY_FALLBACK_FAILED y rollback; causa confirmada por read-only de public.lf_error_knowledge.',
 'DESIGN',
 ARRAY['CLAUDE_NATIVE','PROGRAMADOR'],
 'R2_NO_VE',
 'PROCESS_DEPENDENT',
 'SALY Fabrica Digital F1',
 'https://github.com/cristhianlujan/claude-persona-lf-patch/pull/4850'
)
ON CONFLICT (codigo) DO NOTHING;

UPDATE transversal.error_knowledge
SET evidencia = coalesce(evidencia,'') || E'\n[2026-11-28 SALY F1 PR4847] Un workflow pull_request dedicado no registrado hizo fallar PASE con ordinary pull_request workflows differ: unlisted=saly-creative-item27-semantic-qa-pg17.yml. Se retiro y la prueba PG17 se integro al carrier canónico saly-creative-order-create-pg17.yml; PASE y PG17 quedaron SUCCESS en HEAD 3585885c1af5323ac9d0e1267563e64f51cb16bb.',
    frecuencia = frecuencia + 1
WHERE codigo='PE10_C6_UNAUTHORIZED_GITHUB_WORKFLOW_ENTRYPOINT_V1'
  AND position('2026-11-28 SALY F1 PR4847' in coalesce(evidencia,''))=0;

DO $qa$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_error_knowledge
    WHERE codigo='SALY-F1-SEMANTIC-HASH-DOMAIN-20261128-001'
      AND evidencia LIKE '%78160d6438c2908d469e9ece838b0a14b57eb317b1215cfb702e507e7bbb1f40%'
      AND prevencion LIKE '%creative_assert_dual_qa_l3c%'
  ) THEN
    RAISE EXCEPTION 'SALY_F1_SEMANTIC_HASH_EKB_MISSING';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_error_knowledge
    WHERE codigo='PE10_C6_UNAUTHORIZED_GITHUB_WORKFLOW_ENTRYPOINT_V1'
      AND evidencia LIKE '%2026-11-28 SALY F1 PR4847%'
  ) THEN
    RAISE EXCEPTION 'SALY_F1_WORKFLOW_EKB_READBACK_MISSING';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_error_knowledge
    WHERE codigo='SALY-F1-EKB-NULL-EVIDENCE-APPEND-20261128-001'
      AND prevencion LIKE '%coalesce(evidencia%'
      AND validacion LIKE '%APPLIED=false%'
  ) THEN
    RAISE EXCEPTION 'SALY_F1_EKB_NULL_APPEND_LEARNING_MISSING';
  END IF;
END
$qa$;

COMMIT;
