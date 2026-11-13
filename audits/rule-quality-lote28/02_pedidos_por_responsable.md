# Pedidos listos para enviar — borradores; NINGUNO ENVIADO

**Instrucción transversal para cada responsable:** no hacer DML/DDL, despliegue, cambios de RUN ni producción en respuesta a este documento. Solo devolver evidencia documental, diagnósticos y planes. Toda ejecución posterior requiere operación gobernada separada y autorización explícita, con actor verificado. Proveer rutas exactas, commit/hash, fecha UTC, identidad, RAW y readback cuando aplique. No sustituir evidencias con capturas no verificables o respuestas textuales.

## 1. IG / Plataforma — B09, apoyo a B08 y G15
> **Asunto: LF L28 | Evidencia nativa Router–Perfil–RUN–IG–juez–cierre (solo diagnóstico y plan).** Solicitamos inventario de la ruta vigente ACT-0001 Gate2 → CONTEXT_TRANSPORT → Perfil → RUN → pasos → IG si aplica → Curator/Validator → Step70/OIDC → registro → cierre terminal; diferencias EKB V1.4 vs deployment; fixtures vs runtime; tests positivos/negativos y plan de prueba en entorno gobernado. No crear RUN ni invocar escritores en este pedido. **Devolver:** contratos/versiones y rutas, diagrama con 11 pasos y evidencias obligatorias, especificación de casos negativos, identidad de juez y modo de revisión, método para recibo terminal READY, prueba readback planificada, lista de dependencias B03/B06/B08/B01/B07 y **recibo B09 vacío hasta ejecución autenticada posterior**.

## 2. Dueño LF y dueño SALY — B02, B06, B04, B05, B01, B07, B10, B11, G15
> **Asunto: LF L28 | Decisiones conversadas pendientes de firma y decisiones aún abiertas.** Confirmar firma autenticada por separado de Q01–Q12 y de las 32 preguntas L21 (sin considerar ninguna preaprobada). Determinar cohorte exacta 232/32 conservando el universo hasta reconciliación, owner LF/SALY distinto de SUPER_ADMIN, 15 familias y 23 pertenencias, revisión LF/SALY sin 90/60 sintéticos, 57 pendientes/3 refs/20 pares, política MFA y disparadores faltantes, ledger, Niubiz, cuotas/mora, precios, cartas/aliados, recuperación y umbrales. **Devolver:** actas/versiones con elección literal y exclusiones, firma con actor/sub verificado, lista ID/hash de cohortes, 15+23 veredictos, matriz de responsabilidades y riesgos aceptados, decisión por 32 registros y política de NO-GO/GO posterior. **Ninguna firma aquí autoriza producción**.

## 3. Producto / QA / Finanzas — B10, apoyo a B05/B01/B11/B09
> **Asunto: LF L28 | Especificaciones de negocio y casos QA con fixtures.** Formalizar ledger `payment` padre + `payment_detail` hija, solo INSERT, estado derivado y reversión por eventos compensatorios; Niubiz e integridad de callback; cuotas/cancelación y casos aún NO_DEFINIDOS; pricing versionado y vigencias; carta de no adeudo con los dos modelos de aliado, reenvío y pantalla administrativa por permiso; recuperación con documento, doble aprobación, espera de 48 h y aviso al contacto anterior; umbrales de riesgo en base de datos (5 solo valor inicial propuesto) y pantalla de mantenimiento. **Devolver:** especificaciones versionadas, máquina de estados, SQL/DDL solo de diseño (no ejecutar), matriz decisiones/faltantes, pruebas unitarias/integración/negativas, mocks inequívocamente rotulados, contrato Niubiz/PCI/IDV, conciliación, RACI y evidencia de QA. Los flujos pendientes Q08–Q11 se prueban con datos de muestra sin publicar.

## 4. Legal — B11, apoyo a B10/B01
> **Asunto: LF L28 | Dictamen publicable legal y ciclo de mora/reclamaciones.** Revisar Anexo I, consentimientos, cobro recurrente, política de vencimiento/gracia/reintento/recordatorio/mora/terminación, destino del incobrable coordinado con Finanzas, tratamiento de datos de identificación y recuperación, aviso al contacto anterior, carta de no adeudo y claims/UX. Sin textos o efectos inventados ni publicación de placeholders. **Devolver:** versión íntegra de textos y visuales que aprueba, base normativa identificada, matriz permitido/bloqueado, responsable y firma auténtica, restricciones por canal/aliado, tratamiento de los puntos no definidos y pruebas de no exposición en superficies.

## 5. Seguridad / IAM — B08, B01, B06, B05, B12
> **Asunto: LF L28 | Boundary de identidad, MFA y cuatro permisos no acreditados.** Diseñar/verificar mapeo JWT issuer/aud/JWKS/sub→actor/perfil/proyecto, RLS/GRANT y deny-by-default; descartar HMAC fixture y fallback a session_user. Proponer contrato SAML/IdP administradores, Brevo correo OTP y SMS contingencia (proveedor NO_CONFIRMADO), triggers 30 días sin uso y 3 meses sin cambio de contraseña más casos por definir; fail-closed AUTH-022→AUTH-018 mientras política 19 y destino sigan CANDIDATO. Investigar ausencia reportada en `lf_ops.permisos` de pricing, reenvío carta, aprobación recuperación y parametría riesgo. **Devolver:** SELECT/readback permisos (solo lectura), matriz RBAC roles/recursos/transiciones, plan de creación gobernada *futura* y segregación de funciones; casos de bypass/cross-project/step-up; recibos SAML, proveedor, API/webhook con datos sensibles redactados, pruebas de denegación y firma IAM. No asignar permisos dentro de L28.

## 6. Operaciones / Aliados — B02, B03, B10
> **Asunto: LF L28 | Congelación de cohorte, conciliación por RUN y carta/settlement.** Preparar 232 IDs y subconjunto 32 (si el dueño los designa), hashes/as_of; evidencias individuales preimage/estado/efecto destino/leases/worker/heartbeat, sinks externos y claves idempotentes; plan de gestión de callbacks y conciliación Niubiz, emisión y reenvío de carta para dos modelos de aliado, SLA y alertas. **Devolver:** freeze CSV hash, tabla por RUN con clasificación A/B/C/D revalidada, EFFECT_RECON y LIVENESS por ID, trazas de sistemas externos con custodia, catálogo de excepciones y responsable. No cerrar/reintentar ningún RUN ni atribuir 'sin efecto' por ausencia de log.

## 7. Infra / DBA / Continuidad — B13, B14, B07, B12, B08
> **Asunto: LF L28 | Backup/PITR, restore aislado y compatibilidad (plan y evidencias históricas).** Entregar política real RPO/RTO/retención/cifrado/custodia, IDs y checksums verificables de backups/PITR; diseñar prueba de restore real aislada para autorización separada. Auditar el draft L20 lifecycle (LF 4, SALY 5 con lifecycle_state sin alterar estado VALIDADO), UP/DOWN, backfill, RLS/GRANT, consumidores, rollback seguro; matriz de contratos/regresión de apply_batch, decide_batch, report y guard. **Devolver:** constancias de proveedor y custodia, planes de restore (no ejecución en este pedido), DDL draft versionado sin ejecutar, plan de regresión PG18 y verificación MD5 esperada, no sustituir restore por DOWN; actores y requerimientos de autorización para tareas futuras.

## Formato de retorno requerido (aplica a los 7)
```text
responsable/rol:
bloqueo(s):
documento_fuente + commit/blob:
actor/sub verificado:
alcance y entorno:
evidencia RAW / IDs:
SHA-256 y algoritmo:
prueba positiva:
prueba negativa:
readback:
excepciones/riesgos:
decisiones pendientes:
solicitud de autorización posterior (separada):
firma auténtica / fecha UTC:
```
**Importante:** esta sección es una carta/pedido redactado, no evidencia de que alguien haya recibido ni aceptado la solicitud.

