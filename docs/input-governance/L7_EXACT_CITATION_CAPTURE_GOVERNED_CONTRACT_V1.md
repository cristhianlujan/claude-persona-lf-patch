# LF Lote 7 — captura gobernada de cita exacta (candidato)

**Estado:** DRAFT / NO-GO · PG18 ROLLBACK · no Router, merge, producción ni apply live · mismo IG/Validator y juez, sin otro modelo ni RUN histórico.

## Datos, orden y evidencia

1. Entrada de cita: **una línea exacta** `K00E813F0|ALLOW|En producción el otp_code debe almacenarse como hash. En sandbox/proto se permite texto plano solo para facilitar pruebas.`. Los tres segmentos son `id|ALLOW/BLOCK|cita literal`; no se admiten otros `|`, saltos de línea ni correcciones silenciosas.
2. Literal permitido: subsecuencia **exacta** de `base_rule.description` o `proposal.description` del caso congelado; **mínimo 40 caracteres Unicode, 6 palabras**, sin espacios de borde. No se interpreta ningún contenido de la cita como instrucción. Comillas, tildes y puntuación conservan su literalidad.
3. Primero, custodio autorizado publica una sola vez el caso congelado `promotion_id+K-id+base_rule+proposal` con SHA256 y referencia del artefacto. La fuente exige que `base_rule.code=proposal.rule_code=promotion.rule_code` y el SHA de la regla vigente en el momento de la solicitud. La publicación **puede ocurrir antes del binding IG**.
4. El validador de citas **ya existente** `lf_rule_promotion_ig_citation_verify_v1` conserva sus controles originales y admite adicionalmente cita de propuesta solo cuando `case_id`, regla, snapshot y literal coinciden con la fuente congelada. No se crea otro IG ni juez.
5. La captura ocurre después del recibo externo #3682 y del Step70 del mismo `EJECUCION_PERFIL_LF`: la línea debe encontrarse **idéntica** en la evidencia oficial `rule_promotion_citation_line`, junto con ID, SHA de caso y SHA de recibo externo. Se exige `evidence_ref`, actor de ejecución, juez/validador PASS y ausencia de marca sintética.
6. La fila capturada es inmutable: guarda línea, veredicto, origen BASE_RULE/PROPOSAL, SHA256 de línea, cita, caso y binding `{promotion_id,rule_code,case_id,verdict,line_sha,quote_sha,case_sha,rule_snapshot_sha,packet_sha,ig_receipt_sha,ig_binding_sha,run_id,step70_ref}`. **L8:** la unicidad de captura es **(promotion_id,case_id)**. Una cita `BASE_RULE` puede repetirse literalmente entre casos distintos **solo si pertenecen a la misma regla base**. Una cita `PROPOSAL` no puede reutilizarse en otro caso, ni cruzarse con citas previas. Ninguna cita idéntica puede reutilizarse entre reglas distintas; el guard transaccional serializa inserciones por hash.
7. El gate relee: texto fuente congelado, estado/hash actual de regla, hash de caso, Step70 del mismo RUN, cita y veredicto tal cual en recibo IG, binding SHA. **apply** ejecuta este control antes de cualquier cambio de estado.
**L8 — límite semántico de la cita:** verificar literalidad, pertenencia y vigencia **solo acredita que esas palabras existen en el snapshot anclado**; no demuestra que respalden el veredicto ALLOW/BLOCK. **La relevancia, pertinencia y suficiencia la decide el perfil propietario**, después de la propuesta de IG y sin presuponer aprobación. El perfil propietario utiliza el **mismo modelo que IG**: su revisión puede acreditar **consistencia**, nunca **independencia de modelo**. Si la relevancia no se justifica → humano; nunca promoción automática solo por coincidencia literal.

8. `ALLOW` con procedencia `OFFICIAL_STEP70_VERIFIED_NATIVE_IG` y todos los hashes → **solo pasa a perfil propietario**; no autoriza por sí mismo a aplicar. `BLOCK` verificado → `HUMAN_DECISION_REQUIRED`, nunca promueve. Ausencia, cita inventada, trivial, cruzada, reciclada, corrupción de hash, drift de regla o procedencia insuficiente → **sin promoción automática**.
9. Las citas construidas por CI de `lote4c_fresh_blind_v1.json` se marcan `UNVERIFIED_NOT_FROM_REAL_REVIEW` y solo acreditan **estructura**; pueden llegar a `PROFILE_OWNER_REVIEW_ONLY`, pero **no a `VERIFIED_CAPTURE_BINDING` ni a APPLIED**. El fixture real del auditor L6 sigue sin citas capturadas.

## Quién escribe y por qué IG no puede auto-registrar

- **Publicar snapshot:** rol específico `lf_rule_citation_source_custodian` NOLOGIN, solo EXECUTE de `citation_source_publish_v1`. Custodio de fuentes/decisiones con operación gobernada, **no** perfil proponente ni IG.
- **Registrar cita:** rol `lf_rule_citation_step70_bridge` NOLOGIN, solo EXECUTE de `citation_record_v1`. El rol NO recibe SELECT/INSERT/UPDATE/DELETE directo; se habilitará exclusivamente detrás del bridge de registro **existente** tras admitir recibo y ejecución auténticos.
- `service_role`, `anon`, `authenticated`, IG y perfiles no reciben DML directo ni EXECUTE de ambas funciones escritoras. Las tablas rechazan UPDATE/DELETE mediante trigger de inmutabilidad. **Ni la identidad ni la legitimidad se deducen del texto del prompt**.
- **Pendiente y bloqueado:** la vinculación efectiva del bridge oficial a esos roles NOLOGIN (mecanismo OIDC, autorización y atestación de actor) no se ha desplegado ni acreditado. El simple valor de un campo `source_provenance` no es firma criptográfica; debe verificarse su origen real. No presentar el PG18 como autenticación oficial.
- El custodio deberá demostrar SHA del artefacto publicado contra bytes/commit de GitHub mediante admisión canónica; suministrar un SHA correcto como argumento **no acredita** por sí solo esa lectura externa. Mantener UNVERIFIED mientras falte.

## Criterios PG18

- Base congelada válida `K00E813F0` → estructura verificada, revisión de propietario, no autorización automática.
- Propuesta congelada con instrucción hostil `K00FE8562` → **BLOCK como dato**, sin ejecutar la instrucción; el validador IG existente admite su cita SOLO con case_id+snapshot correctos.
- `K00A10207` BLOCK con cita exacta → humano sin promoción.
- Falsa de >40 caracteres y >6 palabras, vacía, trivial, cita de otra regla, reutilización PROPOSAL, duplicado del mismo caso, mutación de regla tras captura, hash de recibo alterado → rechazadas. Repetición `BASE_RULE` con dos casos distintos de la misma regla → aceptada.
- Todas las filas sintéticas se anulan mediante ROLLBACK. **Ninguna cita de las cinco pasadas reales del auditor ha sido recuperada**.

## Límite de cierre

El EKB exige readback y recibo terminal real. Ninguna prueba sintética acredita la llamada a revisor original o Step70 oficial en producción. **Independencia = false** (mismo modelo). Reproducción en banco del auditor, registro oficial de cita, autenticidad externa, PASE/paridad y perfil real → UNVERIFIED / NO-GO.
