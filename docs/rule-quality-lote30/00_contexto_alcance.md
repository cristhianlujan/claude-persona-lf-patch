# Lote 30 — Registro documental de decisiones del dueño

**Tipo de entrega:** sólo archivos nuevos en rama nueva. **Ni Supabase (sin SELECT), ni producción, ni DDL/DML, ni RUN, ni gates, ni modificación de los archivos previos.**

## Fuente y ruta EKB

- EKB consultado: `INPUT GOVERNANCE LF — INSTRUCCIONES OPERATIVAS V1.4`, estado **CANDIDATO VERIFICADO PARCIALMENTE**. Establece que Router selecciona, Perfil lleva RUN, Input Governance no se invoca directamente desde Router, registrador oficial y recibo terminal son necesarios para cierre; no afirmar independencia sin prueba.
- Repo: `cristhianlujan/claude-persona-lf-patch`.
- Rama nueva: `lf/issue-3779-lote30-owner-conversation-decisions-v1`, **base exacta L29** `bb0779bad18e45a122d70ac17b1ae393080bc7b6`.
- Antecedentes **sólo leídos**: L21/L27 registro de decisiones, L29 `07_login_b2b_matriz_diffs_51.json` y `06_politicas_centrales_mfa_origen.json`. No se acudió a Supabase en L30 ni se ejecutó PG18.
- Autor documental: **GPT-6**, mismo modelo. No alegar identidad Claude, independencia de juez, aprobación formal ni evidencia de cierre.
- El contenido de decisiones Q01, Q02 y Q06–Q12 procede de comunicaciones del dueño en conversaciones. **No son firmas**, no sustituyen recibos, y no equivalen a permisos de ejecución.

## Conteos verificados del registro nuevo

| Tipo | Cantidad | ID |
|---|---:|---|
| Q01, Q02 y Q06–Q12 | **9** | L16-Q01, L16-Q02, L16-Q06..Q12 |
| Modelo de aprobación | **1** | L30-APPROVAL-MODEL-001 |
| **Total L30** | **10** | 10 IDs distintos |
| **Estado decidido en conversación** | **10** | `DECIDIDA_EN_CONVERSACION_PENDIENTE_FIRMA` |
| **Firmas y recibos formales** | **0** | No hay fecha, identidad ni recibo firmado |
| **Reglas oficialmente aprobadas/promovidas** | **0** | No writer/Step70 |

Las decisiones Q03/Q04/Q05 ya constaban como decididas en conversación en el dossier L27; L30 **no las reescribe**. Sobre el universo L16 Q01–Q12, esto deja **12/12 decididas en conversación, 0/12 formalmente firmadas**. Los 20 registros adicionales L19/L21 conservan estado histórico, sin mutación documental aquí. **Subdecisiones pendientes** siguen listadas dentro de Q01/Q08/Q09/Q10/Q11/Q12 y no desaparecen por el estado conversacional general.

## Límites específicos por pregunta

- **Q01:** 30 días sin uso y 3 meses sin cambio de clave son **parámetros centrales**; no se incrustan en reglas. OTP/Brevo principal, SMS contingencia **sin proveedor confirmado**. Otros casos de MFA pendientes. **Admin Empresa perfil 2 → OTP correo; Admin LF perfil 1 pendiente**.
- **Q02:** `payment` padre / `payment_detail` hija, append-only solo INSERT, estado derivado, compensaciones; construcción corresponde a **Producto/QA fuera de IG**. No se diseñan columnas ni se crean tablas.
- **Q06:** documentar 20 pares de parámetros por sujeto/evento/alcance, **sin igualarlos**.
- **Q07:** decidir pertenencia de familia **por dictamen caso a caso**, no remapeo masivo.
- **Q08/Q09:** el desarrollo con **muestras** no equivale a autorización de publicación o producción.
- **Q10:** Carta de No Adeudo con **dos modelos del aliado**, reenvío, pantalla administrativa sujeta a permisos. API/SLA/modelos reales y permiso no acreditados.
- **Q11:** soporte, documento, dos personas, 48 h y aviso contacto anterior; desarrollo con muestras. **Proveedor IDV, recuperación administradores y producción siguen pendientes**.
- **Q12:** parámetro de riesgo configurable en BD con **valor inicial 5**, pantalla de mantenimiento; no se inventa su unidad o el control exacto hasta validarlo.

## Archivos de este paquete

1. `01_registro_decisiones_dueno_l30.json` — 10 entradas estructuradas y estado sin firma.
2. `02_respuestas_conversacion_l30.csv` — espejo de las 10 entradas, mismas firmas vacías.
3. `03_auth019_y_politica19_correccion_propuesta.json` — diffs **antes L29 / después L30**; perfil 2 correo, perfil 1 pendiente.
4. `04_modelo_aprobacion_y_brechas.md` — tabla manual vs sistema, `LF_GOVERNANCE`, prohibición SUPER_ADMIN.
5. `05_comparacion_l27_l30_y_pendientes.md` — overlay y limitaciones de decisión.
6. `06_manifest_sha_readback.md` — cadena de integridad, controles y no-go.
7. `00_contexto_alcance.md` — este archivo.

**Estado final:** DRAFT DOCUMENTAL, decisiones conversacionales no firmadas, propuestas no promovidas, **14/14 bloqueos abiertos**; producción **NO-GO / UNVERIFIED**.
