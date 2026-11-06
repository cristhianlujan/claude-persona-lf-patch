# IG-EVO — Contrato candidato de evaluación profunda R1–R6

Estado: **CANDIDATO / diseño de pruebas**, 2026-11-06. Este archivo no es fuente oficial de negocio, no modifica EKB, Router, políticas ni gobierno de escritura. El trabajo R1–R6 del PR #3680 permanece SHADOW_NON_BLOCKING; **no está listo para reparación autónoma ni para un PASS semántico**.

## Invariantes de arquitectura

- Única ruta: Router ACT-0001 → Perfil → Input Governance (Curator/Validator/T_REMED existentes) → mismo Perfil. El Router solo encamina. El Perfil decide cuándo usar otras capacidades; no se incorpora otro orquestador.
- El detector identifica hechos/hipótesis. Las familias especializadas determinan qué escenarios y autoridades son relevantes. La reconciliación cross-family y el **Validator/ASSURANCE_EVALUATOR nativo** contrastan conclusiones. T_REMED recibe solo casos admitidos.
- Se permite un número variable de escenarios por regla, generado desde recurso/operación, contexto del negocio, estado, dependencias y capacidad; no un “único problema por regla”, ni ocho pruebas universales.
- No escribir automáticamente fuentes canónicas, promover políticas CANDIDATO, alterar T_REMED ni inventar un juez; una regla que parece definida no prueba implementación.

## Contrato por regla (análisis completo, no solo completar campos)

1. **Identificar el sujeto de evaluación.** Negocio (LF/B2B/B2C…), módulo, pantalla, código de operación, actor/perfil, estado, entornos, versión de contrato y snapshot; resolver alcance desde `applicability_v1` y el resolver efectivo autorizado. Un vínculo `DERIVED_GLOBAL` no demuestra aplicabilidad gobernada.
2. **Recuperar el grafo de referencias.** Regla origen → reglas referidas (incluyendo arrays y JSON anidado) → políticas por ID → vínculo de política con operación/pantalla → contratos y decisiones → pruebas de implementación. Registrar código, tabla, PK, campo JSON, estado VIGENTE/CANDIDATO, hash, fecha, origen y saltos fallidos. No omitir una política vinculada ni inferir promoción.
3. **Determinar obligaciones y autoridad.** Separar requisitos obligatorios para el alcance (ley/norma aplicable y LF ratificado), buenas prácticas OWASP/NIST condicionadas por el tipo de sistema, decisiones LF, y preferencias de diseño. Registrar referencia precisa, edición o versión, tipo (NORMATIVE_WHEN_APPLICABLE / NONBINDING_GUIDANCE / LF_DECISION), applicability y si la autoridad fue comprobada. Una recomendación no se convierte automáticamente en incumplimiento.
4. **Generar escenarios.** Para cada capacidad, producir escenarios normales, bordes, negativos, amenazas, combinaciones entre capas y casos de metamorfismo; crear hipótesis adicionales cuando aparezca evidencia, no limitarse a catálogo rígido. En Login: múltiples redes por cuenta, varias cuentas por red, NAT legítimo, éxitos/fallos/anti-bot/reintentos, concurrencia, ventanas/burst, caída de proveedor, señales combinadas. En OTP: emisión, reenvío, operaciones separadas, entrega, deduplicación y enumeración. Fuera de autenticación se aplican otras familias.
5. **Evaluar por escenario.** Registrar `scenario_key`, precondición, input controlado, expected/observed, fuentes, controles existentes, prueba positiva, contraejemplo, severidad fundada, confianza, cobertura de mitigación y estado. Estados separados: DEFINITION (ABSENT/DECLARED_CANDIDATE/DECLARED_VIGENTE), IMPLEMENTATION (NOT_TESTED/EVIDENCED/NOT_PROVEN), ADVERSARIAL (NOT_TESTED/REFUTED/REPRODUCED). No asignar COMPLETE por keywords o `SCREEN_RULE_SET`.
6. **Reconciliar familias.** R1 no dictamina seguridad; R2 valida conflictos reales; R3 resuelve dependencias; R4 contrasta equivalencia funcional; R5 autoridad de selector; R6 aplica abuso y escenarios de ataque. Todos comparten `finding_root_key`. Reutilizar defeaters versionados de ASSURANCE_EVALUATOR para casos entre familias con positivos y negativos.
7. **Juzgar y admitir.** El Validator nativo exige cobertura, calidad semántica, contraejemplos y readback. PASS de hash/readback significa SOURCE_INTEGRITY_ONLY; nunca promueve seguridad. Una fuente candidata solo acredita control declarativo, no backend implementado. Si la evidencia es insuficiente: NOT_TESTED / BLOCKED_AUTHORITY / BOUNDED_EVIDENCE_REFRESH; no inventar corrección.
8. **Entregar al reparador.** Crear packet agrupado por causa y editable solo por proceso gobernado: fuentes exactas, valores, políticas y estados, decisiones, escenarios evaluados, protecciones existentes, faltantes, hipótesis no probadas, parche mínimo condicionado, criterios de aceptación, pruebas y ruta/readback. Reducir el informe general a índice; detalles completos solo del caso asignado.
9. **Comparar corridas.** `NEW/RECURRING/CHANGED/RESOLVED` requiere IDs estables, fuente versionada y packet anterior comparable. `CHANGED_SNAPSHOT` no equivale a `NEW_FINDING`. No recertificar RUN históricos ni ocultar hallazgos antiguos sin prueba.
10. **Métricas.** Precisión (falsos positivos/negativos), cobertura de escenarios, latencia y CPU/buffers por detector, tamaño de índice/packet, y tokens aproximados entregados por destinatario. Registrar p50/p95 solo con muestras múltiples. El costo se optimiza por caché de fuente versionada y consultas deterministas, no omitiendo seguridad.

## Responsabilidad por detector y condición mínima de calidad

| Detector | Profundidad exigida | Evidencia mínima |
|---|---|---|
| R1 PROCEDENCIA | Valores, semántica exacta de qué evento se cuenta, parámetros numéricos/anidados, independencia de contadores, criterio de origen | Tabla/PK/campo, estado vínculo, policy ID, hash, decisión acreditada, validación por campo |
| R2 CONFLICTO | Misma operación/alcance, obligación semántica, excepciones, precedencia, contradicciones **entre familias** | Dos fuentes con autoridad, valores/oposición aplicable, positivo y contraejemplo |
| R3 DEPENDENCIA | Referencia simple/anidada/código/ID, destino no encontrado, versionamiento, estatus, ciclos | Ruta JSON, grafo, IDs, estados, impacto de promoción, alcance |
| R4 REDUNDANCIA | Comportamiento/efecto y configuración equivalentes o incompatibles; título idéntico no basta | Dos fuentes completas, propiedades comparadas, caso discriminante |
| R5 APLICABILIDAD | Resolver declarativo y contexto; no inferir globalidad por bandera | Binding origin, selector, autoridad, pantallas afectadas y contraejemplo |
| R6 SEGURIDAD | Cadena regla→política→binding, controles existentes, varios escenarios adversariales por operación y evidencia de enforcement | Grafo de políticas, controles declarados, fuentes OWASP/NIST/LF tipadas, pruebas positivas y negativas, riesgo residual |

## Ejemplo de paquete de evaluación

**Sujeto:** LF / Backoffice B2B / pantalla `B2B-AUTH-001` id51 / operación `AUTH_LOGIN`. **Regla:** `B2B-RULE-AUTH-021` id440, CANDIDATO y `production_authorized=false`, vinculación `LEGACY_EXPLICIT`. **Política numérica:** `RATE-B2B-LOGIN` id1, VIGENTE, vínculo CANDIDATO, `scope_key=IP_USER`, 5 solicitudes/900s, burst 5, `parameter_provenance={}`. **Política de seguridad:** `SEC-B2B-AUTH-ABUSE-PROTECTION` id22 CANDIDATO, vínculo CANDIDATO, prohíbe bloqueo duro por IP única, exige detección distribuida y mitigación de IP compartida. Estas tres fuentes YA existen; no registrar `MISSING_POLICY`.

**Riesgo hipotético:** `IP_USER` podría ser una sola llave por par IP+usuario; con dos redes para un usuario (Wi-Fi/celular) cada par podría tener un contador distinto. No se ha probado que sea así. Necesitamos evidencia de contadores por sujeto/origen **independientes**, eventos efectivamente contados/excluidos, funcionamiento concurrente y mitigación ante NAT legítimo. OWASP Bot Management recomienda buckets separados; NIST SP 800-63B-4 establece limitación de fallos por autenticador/cuenta cuando aplica, **no obliga a una implementación específica de dos buckets**. LF conserva la decisión y los valores.

**Salida esperada:** `CONTROL_DEFINED_CANDIDATE / IMPLEMENTATION_NOT_PROVEN / ADVERSARIAL_NOT_TESTED`. Ocho escenarios iniciales de Login; los futuros se agregan con nueva evidencia o capacidades. Cada prueba identifica fuente, expected, observación, contraejemplo y resultado. Solo admitir reparación concreta si una autoridad verificable indica cuál control falta o cuál implementación incumple; no duplicar valores numéricos en las reglas.

## Contrato mínimo del packet, sin fabricar autoridad

```json
{
  "schema_version": "IG_EVO_REPAIR_PACKET_V1_CANDIDATE",
  "finding_root_key": "IG_EVO_AUTH_ABUSE_440_22",
  "business": "LF",
  "operation_code": "AUTH_LOGIN",
  "source_snapshot_sha256": "FROM_CURRENT_RUN_ONLY",
  "sources": [{"schema": "lf_ops", "table": "politicas_seguridad", "id": 22, "state": "CANDIDATO", "sha256": "REQUIRED_REAL_READBACK"}],
  "authority": {"LF_DECISION": "NOT_VERIFIED", "OWASP": "NONBINDING_GUIDANCE", "NIST": "CONDITIONAL_REQUIREMENTS"},
  "observations": [{"what": "Counter IP_USER", "truth_state": "OBSERVED_CONFIG"}],
  "scenarios": [{"scenario_code": "MULTI_ORIGIN_SINGLE_SUBJECT", "status": "NOT_TESTED", "tests": ["POSITIVE_REQUIRED", "NEGATIVE_REQUIRED"]}],
  "existing_mitigations": ["DISTRIBUTED_ATTACK_DETECTION_DEFINED_CANDIDATE"],
  "missing_evidence": ["COUNTER_KEY_COMPOSITION", "SERVER_ENFORCEMENT"],
  "risk_verdict": "HYPOTHESIS_NOT_CONFIRMED",
  "repair_action": "CONDITIONAL_AFTER_AUTHORITY",
  "gate": "NOT_REPAIR_READY",
  "readback": "PENDING_GOVERNED_WRITER",
  "semantic_judge": "NOT_TESTED"
}
```

Los campos `REQUIRED_REAL_READBACK`, `NOT_VERIFIED` y `PENDING` **son marcadores de falta de evidencia, no hechos ni recibos**. La estructura es un candidato para homologar sobre los campos ya existentes de Input Governance, no una tabla nueva.

## Pruebas de admisión y seguridad

- T01 caso positivo: pantalla 51 RUN 949 (SOLO LECTURA HISTÓRICA), R1 distingue política VIGENTE/vínculo CANDIDATO y R6 encuentra política 22 con 8 escenarios Login.
- T02 caso OTP: pantalla 56 RUN 836, R6 conserva misma política pero selecciona 11 escenarios propios de OTP. No cuenta escenario exclusivo de Login.
- T03 caso no aplicable: pantalla 1 RUN 931 no recibe falsamente el caso específico de abusos de Login.
- T04 RUN inexistente y RUN de pantalla distinta → fail-closed. No usar un RUN histórico como dictamen fresco.
- T05 escenario `PARTIAL` aplicable se detecta; `NOT_APPLICABLE` se excluye sin inventar amenaza.
- T06 regla REFERENCIA política 22 existente → `DEFINED_CANDIDATE`, no `MISSING`.
- T07 si sólo hay control declarado, exigir evidencia runtime antes de `COMPLETE`.
- T08 si fuente sin decisión válida, `BLOCKED_AUTHORITY`, no escribir.
- T09 cambios de IP/usuario/ventana y concurrencia con positivos y negativos: pruebas runtime pendientes, no simular como PASS.
- T10 nuevo RUN con snapshot igual: comparar ID y hash de caso, no afirmar `NEW` por cambio de fecha.
- T11 no ampliar permisos PUBLIC ni cambiar rutas de Router, no alterar política/counter ni abrir nuevos ciclos en T_REMED.
- T12 medir por detector en tres casos y lote, distinguir `EXPLAIN ANALYZE` aislado de p95 validado.

## Estado del PR #3680 al editar este contrato

Implementado y probado por `SELECT`: R1 identifica semántica **no especificada** del contador; R6 cruza reglas/políticas y genera escenarios por recurso (Login 8, OTP recovery 11), sin declarar defectos reproducidos. Negativos de scope agregados a migración (se ejecutarán al aplicar por ruta gobernada).
No implementado: persistencia inmutable por RUN usando writer gobernado; juez semántico independiente habilitado y probado; pruebas adversariales reales de backend; evaluación profunda de R2/R3/R4; comparación semántica de hallazgos NEW/RECURRING/CHANGED/RESOLVED. No afirmar integración LIVE por CI. PR #3679 es dependencia de calidad separada.

Documento maestro: https://docs.google.com/document/d/1_12oOBUfn0Apmng7D9dqC4Nk3ladNJagRVgh2o-adKg/edit
