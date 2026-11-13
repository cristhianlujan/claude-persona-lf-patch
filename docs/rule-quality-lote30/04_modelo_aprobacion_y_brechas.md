# L30 — Modelo de aprobación: decisión del dueño EN CONVERSACIÓN, sin firma

**Estado de la decisión:** `DECIDIDA_EN_CONVERSACION_PENDIENTE_FIRMA`. **Firma formal acreditada: 0**. Este archivo registra el modelo; no crea actores, grants, claims, perfiles, writer ni decisión oficial de producción.

## Matriz literal de autoridad de aprobación

| Origen de la propuesta | Owner decisor indicado por el dueño | ¿Puede aprobar el SUPER_ADMIN? | Estado verificable |
|---|---|---|---|
| **Manual**, presentada por persona | **Dueño de LF** | **NO** | Modelo decidido conversacionalmente; identidad/firma y binding operativo no verificados |
| **Generada por el sistema** | **Owner genérico `LF_GOVERNANCE`** | **NO** | Owner lógico por registrar/autenticar; no afirmar que una cuenta o grant ya existe |
| Sin origen acreditado | **NO SE ASIGNA APROBACIÓN EN ESTE REGISTRO** | **NO** | Clasificación de origen pendiente de contrato verificable; no inventar autoridad |

**Interpretación controlada:** `LF_GOVERNANCE` es el identificador literal comunicado por el dueño para las propuestas generadas por sistema. No implica que sea un usuario Supabase Auth existente, que posea clave/firma, que el motor pueda autoaprobar sin control, ni que cualquier `service_role` o `SUPER_ADMIN` pueda usarlo.

## Antes / después de autoridad documental

| Control | Evidencia anterior (L26/L29) | Decisión L30 | Pendiente para implementación |
|---|---|---|---|
| Aprobación manual | Owner de proyecto HMAC en PG18, no actor real | Dueño LF | Identidad Supabase Auth + asignación owner + recibo |
| Aprobación de propuesta generada | Owner HMAC fixture; sin perfil de actor genérico acreditado | `LF_GOVERNANCE` | Registro del owner genérico, autenticación/alcance, RLS y evidencia no eludible |
| SUPER_ADMIN | Negativos L29 PG18 con denegación | **No aprueba**, para ninguno de los dos orígenes | Prueba E2E con roles reales y revisión de permisos |
| Registrador | L14/L24/L26 fixture de writer y cierre | **Sin cambio en escritor oficial** | Ejecución por registrador oficial + Step70, readback, segregación de funciones |
| Juez/Curator | SQL determinista escrito por GPT-6 | **Ninguna aprobación de juez independiente** | Revisión independiente y recibos verificables antes de promoción |

## Dependencias mínimas, no declaradas implementadas

1. **B08_IDENTIDAD:** acreditar el `sub`/actor/perfil del dueño y del owner `LF_GOVERNANCE`, sin confundir perfil, rol y cuenta técnica.
2. **B06_OWNER:** registrar owner genérico con alcance para propuestas generadas y dueño para manuales; no sobreentender autoridad por jerarquía de `SUPER_ADMIN`.
3. **B09_E2E:** acreditar clasificación del origen en el RUN nativo, vínculo propuesta→decisión→ejecución→firma→cierre con recibos y segregación.
4. **B07/B12:** compatibilidad con lifecycle DB/funciones legacy, sin modificar gates para este lote.
5. **B02/B03:** no reutilizar ni cerrar RUN históricos para simular una aprobación.

**Regla de trazabilidad:** toda declaración sobre estas decisiones aparece en el registro L30 con `firmada=false`, `regla_aprobada=false` y `promovida=false`. No incorporar nombres, correos, tokens ni firmas de actores que no estén acreditados.

**Alcance de este lote:** solo nuevos archivos; `lf_ops` sin SELECT ni DML, producción sin cambios y RUN sin tocar. **B01–B14: 0/14 cerrados. NO-GO / UNVERIFIED.**
