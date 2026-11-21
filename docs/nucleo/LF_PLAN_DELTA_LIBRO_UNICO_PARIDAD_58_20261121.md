# LF — Delta de plan: libro único y diagnóstico global de transición (2026-11-21)
Corrección del dueño 17:19 Lima, transmitida por Claude; ejecución del diagnóstico y PR expresamente autorizada en el turno siguiente. Destino único: núcleo. La política V1 de #4575 (merge f23acb0b88c7b47e9fb44c5b9b077349b46a3178) sigue transitoria, por obligación funcional, sin ampliar precedencia ni diseñar dos libros permanentes. PARIDAD_MIXTA_PENDIENTE es indicador temporal, no certificación ni permiso de retiro.
## Evidencia y método
Base main bf7a1e4b09ac9262bcb088d918787b233bf6af37. PG17.6, transaction_read_only=on; dos llamadas enviadas como BEGIN READ ONLY; SELECT; ROLLBACK; el conector devuelve filas SELECT, no un recibo separado de ROLLBACK. Sin DDL/DML. Función STABLE inspeccionada antes de invocar, consumidor INPUT_GOVERNANCE únicamente diagnóstico, sin ejecutar IG. Matriz reproducible:
```sql
BEGIN READ ONLY;
WITH p AS MATERIALIZED (
 SELECT id,codigo,pr,lf_ops.lf_nucleo_lectura_transicion_v1(id,'INPUT_GOVERNANCE',pr) j
 FROM lf_ops.pantallas CROSS JOIN (VALUES ('DIRECTAS'),('IG_EFECTIVAS'),('CONTRATO_PANTALLA')) v(pr)
)
SELECT id,codigo,pr,j->>'estado' estado,j->>'nodo' nodo,
 jsonb_array_length(j->'nativas') n,
 jsonb_array_length(nullif(j->'respaldo','null'::jsonb)) l,
 j->'reglas'='null'::jsonb reglas_null,md5((j-'fecha')::text) digest
FROM p ORDER BY id,pr;
ROLLBACK;
```
Resultado 58 pantallas, 174 paquetes. Estado por DIRECTAS / IG_EFECTIVAS / CONTRATO_PANTALLA: PARIDAD_MIXTA_PENDIENTE 9/9/9; RESPALDO_COMPAT 44/44/32; RESPALDO_SIN_NODO 5/5/1; SIN_CONTRATO_LEGADO 0/0/16. Cero mixtas con reglas no nulas; 54 apariciones nativas, 18 por proyección. Legadas por proyección: 6177 directas, 15086 efectivas, 11016 contrato (apariciones no reglas únicas; contrato excluye 16 nulos). 58/58 efectivas tienen legado. Compat 586 filas. Mixtas IDs 21,24,25,27,28,30,33,34,59. Sin nodo 8,9,12,26,55; sin contrato 7,8,9,10,12,13,15,16,17,26,36,37,38,39,41,42. Restantes 49 sin nativas. IDs 9 y 26 tienen 0 directas pero 242 efectivas cada una. No interpretar ausencia de contrato como vacío. 0/58 acreditadas listas para retiro. Cobertura publicada no equivale a exigibilidad (desde 2026-12-06) ni implementación.
EKB directa: LF-NUCLEO-MIGRATION-CANDIDATE-LEGACY-COEXISTENCE-20261121-001 y LF-NUCLEO-A4-DIRECT-LEGACY-READER-CI-20261121-001 RESUELTO, aplican como resguardo (no nuevos lectores ni FK); LF-NUCLEO-LEGACY-RULES-NOT-EVALUABLE-20261121-001 y LF-NUCLEO-IG-FAMILIES-WITHOUT-RULES-20261120-001 ACTIVO, impiden certificar retiro, no impiden diagnóstico documental. PROFILE-CREATOR-EKB-PREFLIGHT-MERGE-ORDER-005 y PROFILES-EKB-PREFLIGHT-OMISSION-001 activos, no se ejecutan perfiles; preflight realizado antes de rama. Prevención PROFILES-RULE-EKB-BEFORE-PROBLEM-001 leída; best practice paridad por contenido leída. No cerrar hallazgos. La evidencia previa #4575 12/12 y ocho obligaciones focales se conserva, incluidos dos residuales onboarding REG_TEC_007; no certificar solape por código.
## Camino propuesto
586 legadas clasificadas en 46 etiquetas observadas, 150 pendientes de validación; reconciliar con vocabulario objetivo 36 antes de concluir cobertura. Núcleo LF 2 VIGENTE + 8 CANDIDATA, todas PAYMENTS_CHECKOUT; SALY 14 CANDIDATA. Lotes propuestos por etiqueta legada: checkout 61; ofertas/cuotas 53; integridad financiera 16; seguridad/MFA/sesión/rate limit 112; estados/transiciones 75; legal/privacidad 27; restantes 242. No convertir clasificación propuesta en asignación aprobada. Por lote mapear origen a autoridad, condición/efecto y pruebas, alcance directo/heredado/transversal, preservar residuales; cada candidata por puerta canónica, no copiar texto en masa. Priorizar diagnóstico 5 sin nodo y 16 sin contrato; no crear nodos ni contratos en este PR.
Lista para solicitar retiro por pantalla/familia solo si inventario completo, clasificación validada, todas obligaciones cubiertas por versiones vigentes y exigibles, cero residuales/conflictos, equivalencia certificada independiente, pruebas PG17 positivas/negativas y límites, tres proyecciones comparadas y dependencia/reversión de consumidores identificada. Indicador de transición no altera lectores; autorización posterior separada para cutover/retiro. No ejecutar DP-IG-05, F6, RETIRADA, IG/perfiles, REG_CHK_007 ni juez externo. Paulo: fuentes checkout y resto DP-IG-04. Dueño: comisión LF, acepta_yape_en_cuotas, 25 reglas texto pantalla.
## Tablero
71/100 (+0), S 11/11, F2 8/10 (certificación semántica independiente 0/2), A4 2/4, F4 2/3, DP-IG 3/5 separado. Diagnóstico global 58/58; no añade criterio de cierre ni certifica paridad. PR documental exclusivamente; no cambio BD ni runtime. 
