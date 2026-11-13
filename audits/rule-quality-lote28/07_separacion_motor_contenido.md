# L28 — Separación de responsabilidades: GO del Motor vs avance de Contenido

**Estado: actualización documental del plan; no cambia contratos oficiales ni evidencia previa.**
**Objetivo:** permitir cerrar el motor de Input Governance sin bloquear su pase técnico por firmas de reglas, MFA, negocio o legales; conservar todas las dependencias técnicas y mantener las funcionalidades de Contenido sin activar hasta sus propias autorizaciones.

## 1. Grupos cerrados (14 IDs, sin duplicados)

| Grupo | Bloqueos | Resultado que se mide | Estado conocido |
|---|---|---|---|
| MOTOR | B02_RUN_SCOPE, B03_RUN_EFFECTS, B06_OWNER, B07_SCHEMA, B08_IDENTITY, B09_E2E, B12_LEGACY, B13_BACKUP, B14_RESTORE | GO/NO-GO **técnico de Input Governance** por 9 recibos y G15-MOTOR | 0/9 CERRADOS, NO-GO |
| CONTENIDO | B01_MFA, B04_FAMILY, B05_RULES, B10_BUSINESS, B11_LEGAL | Desarrollo/validación/registro por IG en paralelo. Firma documental para **ese contenido**, no pase del motor | 0/5 CERRADOS |
| Total histórico | B01–B14 | Gestión integral por separado, no fórmula de release IG | 0/14 CERRADOS |

## 2. Criterios

**Gate MOTOR:** G01 (B02), G02 (B03), G03 (B06), G04 (B08), G08 (B12), G09 (B13), G10 (B14), G11 (B07), G12 (B09); se exige además **G15-MOTOR** = autoridad de despliegue, pruebas negativas, rollback, alcance técnico y operación futura aprobada. **Se excluyen del gate Motor** G05 (B01), G06 (B04), G07 (B05), G13 (B10), G14 (B11), así como las firmas de Contenido que aparezcan entre las 32 decisiones L21.

**No liberado por GO de Motor:** funcionalidades de Login/MFA que aún dependan de AUTH-018/policy 19 candidatas; precios, pagos, contratos, carta, recuperación y reglas de negocio sin aprobaciones; claims legales/UX. Toda función de Contenido no acreditada permanece **CANDIDATO, no publicada, deshabilitada o fail-closed** según su contrato. No usar fixtures como autorización productiva.

**Firma del dueño:** distinguir (a) aprobación de propiedad, identidad, cohorte, backups, migración y pase del **Motor**, requerida por sus controles; (b) decisión de diseño/contenido Q01–Q12 u otras, registrada en IG, **sin veto para G15-MOTOR**. Ninguna decisión en conversación equivale a firma autenticada.

## 3. Dependencias preservadas y condición de no-bypass

| Arista heredada | Conservada como | Evidencia exigible **al Motor** | No exige |
|---|---|---|---|
| B04 → B07 | Contrato de modelo de familia/categoría, campos/refs y segregación LF-SALY | Prueba de esquema/carga/rollback compatible con taxonomía disponible o fixtures versionados; sin migrar membresías no autorizadas | Cierre B04, 15 familias y 23 veredictos firmados |
| B05 → B12 | Baseline semántico y contratos legacy de reglas existentes | Diff firmas/comportamiento de 4 funciones y suite de regresión sobre baseline trazable, preservación gates MD5 | Resolver y firmar 57 pendientes, 3 refs, 20 pares como cierre B05 |
| B01 → B09 (si Login) | Prueba de ausencia de bypass MFA al ejecutar ruta nativa | AUTHENTICATED nunca prematuro, step-up/fail-closed, alcance de ensayo claramente limitado, cero publicación MFA no vigente | Promover AUTH-018 o firmar por completo B01 |
| B06-D → B08 → B06-A | Separación de diseño y activación real de owner | Owner real identificado, actor/sub auténtico, RLS/GRANT y negativos cross-project/SUPER_ADMIN | Asignación por defecto ni owner simulado |
| B02 → B03 → B09 | RUN scope y efectos seguros | Freeze IDs, reconciliación con readback, no cerrar ni reintentar RUN preexistentes | Usar fixtures para encubrir efectos |
| B13 → B14 → B07 | Backup y restore antes de esquema | Backup físico/PITR y restore aislado con integridad/RPO/RTO | Declarar DOWN = restore |

**Regla de bloqueo:** si la interfaz familiar, baseline semántico, identidad o MFA fail-closed falla o no puede probarse donde el Motor lo necesita, **B07, B12 o B09 no se cierran**. No se sustituye esa evidencia por firma de Contenido ni se excluye de las pruebas. El plan cambia el **nivel de aceptación**: compatibilidad técnica del Motor frente a cierre funcional/documental del Contenido, no borra las aristas.

## 4. Fórmulas y readback

- **Motor:** 0/9 bloqueos completos (0 %) y 0/9 gates técnicos, más G15-MOTOR pendiente → **NO-GO**.
- **Contenido:** 0/5 bloqueos y 0/5 gates documentales → progreso paralelo. Sus firmas faltantes **no incrementan ni reducen** 0/9 del Motor.
- **Conjunto histórico:** 0/14 bloqueos y 0/15 gates L21; **sin revalidación** de bases vivas. 0/32 firmas L21 documentadas en fuentes originales, pero **no se pide 32/32 para GO técnico IG**.
- **12 etapas**: A LF nueva 5/12 real sandbox, B LF corregida 5/12 real sandbox, C SALY nueva 5/12 real sandbox; conjunto 15/36 REAL_EN_SANDBOX (41,7%), 14/36 sintéticas, 7/36 no probadas y 0/36 E2E productivas acreditadas en L18/L20. No modificar cifras por un cambio de plan.
- **MD5 PG18 históricos preservados (no leídos live aquí):** apply `86b0494984edf95cf0f9c0a0df67000b`, capture_record `89cbfac4162dbc9f8ecca59f2c3ab4c3`, citation_verify `773a62783baa5edbe967200cac66b8c3`, l8_guard `522d12f0843be1da3c785cef3c0bf3fc`.

## 5. Límites de autoridad y activación

El L21 `04_go_no_go_firmable.md` **sigue diciendo G15 global = 14 recibos + 32 firmas**. Este documento no lo altera ni afirma que G15 operativo admita el alcance Motor. **Antes de utilizar G15-MOTOR para una liberación real**, el responsable de gobernanza debe aprobar el nuevo scope, demostrar quién puede autorizarlo y verificar/corregir por ruta oficial cualquier gate en Supabase/código que siga imponiendo el cierre global. Si la revisión falla o falta evidencia, NO-GO. El dueño no ha emitido en esta actualización una firma técnica autenticada ni permiso de producción.

**Alcance de esta actualización:** documentos en la rama L28 únicamente. No SQL, no escritor, no RUN, no permisos, no deploy, no merge, no fechas, no ejecuciones ni pruebas nuevas de PG18.
