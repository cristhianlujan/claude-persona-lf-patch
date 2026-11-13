# Lote 30 — Comparación con L21/L27/L29 y pendientes reales

## Cambios de estado de decisión (NO de reglas en Supabase)

| Universo L16 (12 Q) | Antes L27 | Después L30 como overlay documental |
|---|---:|---:|
| Decididas en conversación, sin firma | 3 (Q03/Q04/Q05) | **12 (Q01–Q12)** |
| Q01 solo recomendación C sin confirmar | 1 | **0**; ahora hay decisión conversacional sobre MFA, NO confirmación retroactiva de opción C |
| Q02 y Q06–Q12 pendientes en L27 | 8 | **0** como preguntas sin decisión conversacional; siguen subasuntos técnicos pendientes |
| Firmadas formalmente | 0 | **0** |
| Adicionales L19/L21 (fuera de este lote) | 20 pendientes | **20 pendientes**, sin editar |
| Modelo de aprobación genérico | No registrado como decisión L16 | **1 registro adicional L30**, no inventa firmas |

**Sobre 32 decisiones heredadas L21:** 12 discutidas/decididas, 20 pendientes, **0 firmadas**. Además se documenta por separado 1 decisión de aprobación `L30-APPROVAL-MODEL-001`; **no agregarla a las 32** al comparar denominadores. Los archivos originales L21/L27/L29 siguen inalterados.

## Decisión conversada vs. paso a producción

| Pregunta | Contenido ya decidido | **No decidido / pendiente** |
|---|---|---|
| Q01 | OTP correo/Brevo; SMS contingencia; MFA condicional 30 días / 3 meses en política central; perfil 2 OTP correo | Otros disparadores MFA, proveedor SMS, método Admin LF perfil 1, binding/QA |
| Q02 | `payment` / `payment_detail`, solo INSERT, estado derivado, reversión compensatoria; Producto/QA construye fuera de IG | Construcción y pruebas reales, ledger de producción |
| Q06 | Documentar pares sin igualar valores | Dictamen y trazabilidad de 20 pares |
| Q07 | Familia por dictamen individual | Resolver y acreditar cada pertenencia dudosa |
| Q08 | Desarrollo con muestras | Legal aprueba versiones publicables de consentimientos/Anexo I |
| Q09 | Desarrollo con muestras | Claims, copys, rutas y visuales de Home con respaldo publicable |
| Q10 | Dos modelos de Carta No Adeudo, reenvío y pantalla según permisos | Modelos del aliado, API/SLA, permisos reales, QA |
| Q11 | Soporte+documento+2 personas+48h+aviso al contacto anterior | Proveedor IDV y integración real; alcance Admin LF/IdP pendiente; producción |
| Q12 | Parámetros BD, valor inicial 5 y pantalla de mantenimiento | Unidad/control concreto, calibración/telemetría y permiso de riesgo |
| Modelo | Manual→dueño; sistema→`LF_GOVERNANCE`; SUPER_ADMIN→sin aprobación | Identidad/roles/segregación y recibos verificables |

## AUTH-019 y política 19 — incompatibilidad que no se debe ocultar

La **propuesta L29** asociaba perfiles **1 y 2** con Google Workspace SAML 2.0. La **decisión correctiva L30** retira esa suposición para el perfil 2, que debe usar **OTP por correo/Brevo**, mientras **perfil 1 continúa SIN MÉTODO CONFIRMADO**. El diff íntegro se publica solo como nuevo archivo `03_auth019_y_politica19_correccion_propuesta.json`; no se edita el original L29 ni la fuente `lf_ops.reglas`.

La política central de factor del origen L29 define requisitos fuertes contra phishing para administradores. **Una selección de OTP por correo no prueba por sí misma equivalencia con ese requisito**. No se deshabilita el control existente: queda `REQUIERE_REVISION_SEMANTICA_SEGURIDAD`. También requieren reconciliación AUTH-018, AUTH-033 y cualquier consumidor de política 19. Ningún bypass ni OTP declarado como AAL2 nativo.

## Estado de gobierno

- `DECIDIDA_EN_CONVERSACION_PENDIENTE_FIRMA` **no** equivale a `APROBADO`, `FIRMADO`, `PROMOVIDO`, `VIGENTE` ni `GO`.
- El sistema no recibió nuevas identidades. `LF_GOVERNANCE` se registra como **owner lógico designado**, no cuenta Supabase Auth acreditada.
- No reabrir ni cerrar RUN. No cambiar gates. Sin nuevo SELECT ni escritura Supabase; no se reclamó CI nueva ni E2E productivo por un lote documental.
- **0/14 bloqueos de producción cerrados**, B01/B06/B07/B08/B09/B12 siguen abiertos; backup/restore tampoco acreditados.

**Dictamen: REGISTRO DOCUMENTAL LISTO, AUTORIDAD FORMAL Y EJECUCIÓN NO VERIFICADAS. NO-GO / UNVERIFIED.**
