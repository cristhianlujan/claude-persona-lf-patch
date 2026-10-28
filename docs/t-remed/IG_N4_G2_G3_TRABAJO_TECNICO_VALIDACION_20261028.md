# LF Input Governance — G2/G3: implementación candidata y verificaciones

**Fecha:** 2026-10-28 · **Rama:** `dev/ig-n4-tremed-cascade-governed-20261028` · **PR:** #3269 (DRAFT) · **NO RECLASSIFY / NO ROUTER / NO DB WRITES**.

## Resultado y límites

Se diseñó código correctivo para endurecer **las funciones actuales de N-4**, sin crear un motor de herencia alternativo. Se agregaron pruebas de admisión y composición como **referencias de contrato** (no autorización ni ejecución operativa). Las verificaciones SQL se realizaron en **SELECT read-only**; las funciones nuevas **no se ejecutaron como DDL** en PostgreSQL. Por tanto **NO DECLARAR G3 PASS INTEGRAL NI PRODUCCIÓN**.

## Artefactos versionados

| Artefacto | Propósito | Estado |
|---|---|---|
| `sandbox/lf_contract_gate_test/input_governance/ig_n4_clause_matcher_hardened_candidate_20261028.sql` | Candidato SQL `BEGIN ... ROLLBACK`, guardas de MD5, helper mínimo de validación de estructura, actualización de dos funciones N-4 existentes. Rechaza JSON null, claves extra, rutas incorrectas, consumer roles no textuales, y valida todas las cláusulas ANTES de corto circuito OR. | Código escrito, **NO ejecutado** en PG aislado/producción |
| `sandbox/lf_contract_gate_test/input_governance/ig_n4_preclass_synthetic_matcher_v2_20261028.sql` | 27 vectores adversariales del matcher actual. | Ejecutado contra N-4 vivo en SELECT |
| `sandbox/lf_contract_gate_test/input_governance/ig_n4_matcher_hardened_select_only_shadow_20261028.sql` | Implementación de contraste por CTE SELECT del comportamiento correctivo, sin reemplazar funciones. | Ejecutado; 27/27 conforme |
| `sandbox/lf_contract_gate_test/input_governance/ig_n4_scope_admission_conflict_reference_tests_20261028.js` | Referencia pura para conflicto, veto, recibo exacto, expiración, autorización condicional y cobertura independiente. | 35 pruebas ejecutadas con `Function` aislado, 0 discrepancias |
| `docs/t-remed/IG_N4_TREMED_G2_AUDITORIA_Y_AJUSTES_DE_CONTRATO_V21_20261028.md` | Análisis previo F01–F06 y condiciones H16–H21. | Base de diseño; ratificación pendiente |

## Evidencia de pruebas

| Prueba | Resultado real | Interpretación |
|---|---|---|
| Matcher N-4 vigente, 27 vectores | **18 PASS / 9 FAIL** respecto del nuevo contrato | Detecta brechas de `null`, cláusula desconocida, OR, consumer roles numéricos y selector que admite `EXISTS(target)` |
| Sombra `SELECT` de diseño endurecido, mismos 27 | **27 PASS / 0 FAIL** | Comparación semántica de PostgreSQL en lectura; **no** es ejecución DDL de funciones candidatas |
| Comparación de 14 ACTIVE × 58 pantallas | **812 comparaciones, 52 coincidencias actuales, 52 candidatas, 0 diferencias** | Paridad del matcher en datos vigentes. La consulta ejecutó correctamente; **guardar su fuente completa en GitHub fue bloqueado**, por lo que se debe materializar reproducibilidad antes de certificar |
| Referencia JS de admisión | **25/25** | Verifica solo lógica de modelo con **dobles** de fuente de autoridad y de inspector de cobertura |
| Referencia JS de composición/conflictos | **10/10** | Diferencia acumulación, duplicado, conflicto, veto, excepción aprobada por doble y `MODEL_GAP` |
| Validación de funciones PostgreSQL aislado | **NO EJECUTADA** | Falta compilar, revisar grants/helper y ejecutar pruebas en instancia desechable |
| Recibo gerencial auténtico | **NO VERIFICADO** | No hay adaptador conectado a autoridad/owner real; ningún `APPROVE` real creado |

### Detalle de nueve diferencias N-4 actual

T07: `EXISTS` de JSON null; T08: `EQ(null)`; T09: `IN([null])`; T22: `EXISTS(target)` sin restricción; T23: propiedad de cláusula desconocida; T24: cláusula inválida oculta en `any` después de una coincidente; T25: `null` inválido oculto en `any`; T26: operador desconocido oculto en `any`; T27: `consumer_roles` acepta número convertido a texto.

**T22** ahora es parcialmente rechazado por la gramática (ruta solo `target`), pero una condición amplia no tautológica necesita todavía el **control de publicación**. No confundir la sintaxis del selector con autoridad de scope.

## Resultados conservadores y seguridad de diseño

- No crear campos obligatorios de sesión o módulo para las pantallas.
- Las 17 cláusulas de los 14 selectores ACTIVE observados no usan `EXISTS`, literales null ni propiedades desconocidas. El contraste directo 812/812 sin diferencias ofrece tranquilidad **limitada al baseline actual**.
- **No** confiar en `is_broad_coverage` declarado por el solicitante: la referencia JS obliga a recibir resultado de un inspector de cobertura independiente, atado a hashes de regla, selector y scope. El inspector de pruebas es **simulado** y no autoriza publicación real.
- Las reglas compatibles se acumulan, las duplicadas exactas se proponen para deduplicación sin perder procedencia; conflictos sin precedencia verificada permanecen HOLD; política superior no delegable tiene veto incluso ante excepción.
- `READY_FOR_GOVERNED_PUBLICATION` en JS significa candidato para revisión, **NO** `ACTIVE` ni permiso DB.
- Los esquemas existentes de `human_decisions` y `authority_attestations` se revisaron antes; sigue pendiente demostrar que sirven para scope de regla, sin inventar otro motor.

## Gates pendientes de forma precisa

1. **G2:** ratificar contrato de JSON null/ausencia, gramática y límites de selectores; revisar caso de excepción legítimamente universal.
2. **G3/PG:** ejecutar el script SQL en una instancia PostgreSQL aislada con ROLLBACK, verificar plan y permisos, ejecutar 27 casos contra la función efectiva y comparar las 812 combinaciones con fuente exacta.
3. **G3 integración:** validar con casos reales y una revisión independiente las colisiones, políticas, cambios de estado de regla, consumers externos, negativa/UNKNOWN y selector de familias; no basta con los 35 tests JS.
4. **G4:** definir y probar un vínculo **real** con la autoridad de gerencia/owner y el inspector de cobertura; probar veto, caducidad, autorización parcial y revocación, no usar dobles en producción.
5. **G5:** solo entonces iniciar reclasificación real, por metodología ratificada. No tocar el SQL previo de eliminación masiva de `DERIVED_GLOBAL`.

**Estado de cumplimiento:** desarrollo de código y pruebas aisladas avanzado; G2/G3/G4 todavía pendientes; G5 bloqueado. Supabase sigue con el matcher original y su herencia intacta.
