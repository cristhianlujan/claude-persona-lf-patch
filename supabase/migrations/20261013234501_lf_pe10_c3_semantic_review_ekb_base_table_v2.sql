-- PE10_C3: append-only EKB on canonical transversal.error_knowledge base table.
-- Supercedes failed unmerged PR #2537: view-write and invalid family codes. No change to frozen evidence, reviewer or policy.
DO $ekb$
BEGIN
  INSERT INTO transversal.error_knowledge
    (id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,
     validacion,severidad,frecuencia,primera_vez,ultima_vez,lote_origen,pr,
     estado,evidencia,created_at,updated_at,root_cause_family,source_context,source_ref)
  SELECT gen_random_uuid(), v.codigo,'PROFILE_EVOLUTION',v.titulo,v.descripcion,v.causa,
         v.patron,v.prevencion,v.validacion,'HIGH',1,clock_timestamp(),clock_timestamp(),
         'PE10_C3',v.pr,'ACTIVO',v.evidencia,clock_timestamp(),clock_timestamp(),
         v.familia,'SEMANTIC_REVIEW',v.pr
  FROM (VALUES
    (
      'LF-PE10-C3-EMPTY-COMPOSITION-SCORER-20261013-001',
      'PE10_C3: MODE_CONTRACT_COMPLETE trataba composicion vacia como contrato incompleto',
      'En PEB2-004/005/006 el selector congelado eligio cero capacidades opcionales, pero el scorer exigia lista no vacia.',
      'El validador V1 aplicaba ec[k] not in (None, [], {}, empty_text) a capabilities_applied independientemente de la decision del selector.',
      'EMPTY_COMPOSITION_MISCLASSIFIED',
      'En V2 aceptar lista vacia solo con decision tipada NO_ADDITIONAL_CAPABILITY_NEEDED, justificacion y refs compatibles; no permitir omitir capacidades obligatorias; V1 y evidencia historica inmutables.',
      'Pruebas aisladas positivas y negativas V2 7/7 PASS; los 3 casos congelados continuan historicos y la revision independiente no se autoadmite.',
      'https://github.com/cristhianlujan/claude-persona-lf-patch/pull/2534',
      'SOURCE_V2_CANDIDATE_UNMERGED_NO_RUNTIME_ACTIVATION',
      'UNCLASSIFIED_WITH_REASON',
      'https://github.com/cristhianlujan/claude-persona-lf-patch/pull/2534'
    ),(
      'LF-PE10-C3-SEMANTIC-SHAPE-ONLY-20261013-001',
      'PE10_C3: handoff independiente aceptaba PASS con forma sin comparacion RAW',
      'El intake del handoff candidato aceptaba un PASS semantico con solo justificacion y refs arbitrarias, sin pares de salida original/evolucionada.',
      'El intake validaba forma, contexto e independencia declarada, pero no exigia una base conductual RAW trazable para un resultado favorable.',
      'SEMANTIC_PASS_WITHOUT_BEHAVIORAL_BASIS',
      'Para PASS exigir pares RAW identificables, refs incluidas en evidencia del revisor, mejora observable y cero regresiones criticas declaradas; FAIL sigue registrable; procedencia proveedor se verifica por autoridad externa.',
      '13/13 pruebas positivas/negativas PASS; PR 2536 merged via Train; readback de dos blobs en main; ni atestacion GPT Native ni C3 cerrado.',
      'https://github.com/cristhianlujan/claude-persona-lf-patch/pull/2536',
      'CODE_ONLY_MERGED_TRAIN_PROVENANCE_STILL_UNVERIFIED',
      'UNCLASSIFIED_WITH_REASON',
      'https://github.com/cristhianlujan/claude-persona-lf-patch/pull/2536'
    )
  ) AS v(codigo,titulo,descripcion,causa,patron,prevencion,validacion,pr,evidencia,familia,source_ref)
  WHERE NOT EXISTS (
    SELECT 1 FROM transversal.error_knowledge e WHERE e.codigo=v.codigo
  );
  IF (
    SELECT count(DISTINCT codigo) FROM transversal.error_knowledge
    WHERE codigo IN (
      'LF-PE10-C3-EMPTY-COMPOSITION-SCORER-20261013-001',
      'LF-PE10-C3-SEMANTIC-SHAPE-ONLY-20261013-001'
    )
  ) <> 2 THEN
    RAISE EXCEPTION 'PE10_C3_EKB_READBACK_FAILED';
  END IF;
END;
$ekb$;
