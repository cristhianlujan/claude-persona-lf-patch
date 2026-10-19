# G2B — operación de prueba autónoma sobre infraestructura protegida existente

**Autorización:** aprobación del usuario en la conversación, exclusivamente fixture G2B aislado. No se autoriza explotación de fuentes reales ni G3. EKB consultado: `IG-M107-FROZEN-CONTEXT-FINAL-COMMIT-FENCE-019`, `IG-M107-G2B-FIXTURE-ATOMIC-GATE-020`.

**Ruta de transporte:** ejecución confiable ya habilitada por `.github/workflows/lf-ig-runtime-candidate-judge.yml` (base/main, `environment: lf-ig-judge`, cliente psycopg instalado, target gobernado). **No se modifica el workflow ni se crea lector de credenciales**. Se agrega un modo explícitamente discriminado por el schema `LF_IG_G2B_TWO_SESSION_REQUEST_V1` al helper que el workflow ya invoca. El contrato previo N9 continúa exactamente para sus solicitudes normales: una conexión, rollback, sin cambios de comportamiento.

**Este modo G2B es una operación de prueba distinta de N9**, no una concesión de N9 a escrituras arbitrarias. El helper confiable solo admite el JSON exacto y fijo: `FIXTURE_ONLY`, tabla `programacion.input_g2b_source_fixture_v1` y caso `IG_M107_G2B_TWO_BACKENDS_001`. No admite SQL, Python, comandos o identificadores de PR como parámetros operativos. La fuente del ejecutor debe estar fusionada en main ANTES de presentar el PR de solicitud. Los cambios del PR solicitante solo transportan JSON bajo los checks actuales del workflow y no pueden ejecutar código propio.

## Prueba material esperada

- Preflight fail-closed: EKB vigente, MD5 exacto de la función de cierre y trigger, 21 triggers canónicos sin cambios, fixture inicialmente vacío, dos backends distintos y READ COMMITTED.
- Sesión A congela instantánea de fixture y registra una aceptación positiva; sesión B verifica el COMMIT.
- Sesión A congela fuente A; sesión B modifica fuente en fixture y realiza un COMMIT real; sesión A reconsulta y obtiene época 2, rechaza época 1, contrato falso, identidad cruzada, SHA falsificado y acepta época 2.
- Sesión A toma `FOR UPDATE` en el cierre y mantiene transacción abierta; sesión B intenta cambiar la fuente, queda bloqueada; solo tras el COMMIT A se libera B; la nueva fuente incrementa época e invalida el cierre anterior.
- Tres UUID aleatorios insertados **solo** en fixture y luego eliminados; 0 registros residuales post-ejecución, error si no limpia. Ninguna tabla de reglas, contratos, usuarios, pantallas ni results de Input Governance recibe DML.
- Evidencia solo del alcance de fixture; **G2B global sigue pendiente** hasta probar cobertura de escritores reales y validar rendimiento/semántica antes de G3. Nunca auto-declarar PASS global ni CP3 DONE por este recibo.

**Procedimiento:** PR del helper sin workflow/credenciales por LF Migration Merge Train; tras fusión verificada, PR de solicitud exacta `sandbox/ig_cv/n9_requests/request.json`; el workflow protegido se activa automáticamente por `pull_request_target`. Inspeccionar el job `run-ig-n9-when-applicable` y stdout del comprobante, luego cleanup/readback Supabase. Las dos rutas usan el código confiable de main, no contenido ejecutable de PR. Ninguna operación adicional sobre credenciales o workflow.
