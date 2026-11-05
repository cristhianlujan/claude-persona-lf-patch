# Propuesta para Cristhian — Selector de perfiles para Programación

**Proyecto:** LF · Fase 2, Programación  
**Origen:** experimento aislado del PR [#3666](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3666)  
**Estado:** `EXPERIMENTO_APROBADO_PARA_PROPUESTA`, según revisión independiente de Claude. **No es aprobación para producción ni para fusionar.**

## 1. Problema que queremos resolver

El selector actual permite descubrir perfiles por canal, pero **no distingue especialidades de programación** (backend, frontend, datos) para un lote de archivos. Hoy, en `PROGRAMACION`, los perfiles disponibles son de diseño; todavía no están registrados los perfiles programadores reales. Por eso no basta con escoger un candidato del canal para saber quién debería trabajar sobre un lote concreto.

También existe un problema de disponibilidad: la preparación original exige que **todos los descriptores canónicos estén completos y vigentes**. Si uno queda desactualizado, puede bloquear la preparación del catálogo completo, incluso cuando el perfil afectado no pertenece al canal solicitado.

## 2. Cambios propuestos al selector de Cristhian

| Cambio | Qué haría | Por qué |
|---|---|---|
| **a) Áreas declaradas por perfil** | Guardar explícitamente las áreas que atiende cada perfil, por ejemplo `BACKEND`, `FRONTEND` o `DATA`, sin inferirlas de su nombre. | Un nombre puede ser engañoso y dos perfiles pueden cubrir la misma área. |
| **b) Reglas de rutas por proyecto** | Mantener una configuración de `project_ref`, área y patrón de archivos. Por ejemplo, Java puede usar `src/main/java/` y otro proyecto `api/app/` para backend. | Cada repositorio organiza su código de forma diferente; las rutas no deben quedar fijas dentro de una función SQL. |
| **c) Filtro determinista antes de la IA** | Clasificar las rutas del lote usando esas reglas, ofrecer **todos** los perfiles elegibles del área y bloquear lotes mixtos (`LOTE_MULTI_AREA_BLOCKED`) o reglas incompatibles (`LOTE_PATH_RULE_CONFLICT`). También bloquear cuando no existe perfil para el área (`NO_PROFILE_FOR_AREA`). | Evita entregar archivos de distintas especialidades a un agente equivocado, sin decidir por adelantado cuál candidato elegir. |
| **d) Validación de la elección** | Revalidar proyecto, rutas, área, candidatos y recibo; bloquear si la IA selecciona un perfil fuera del área declarada. | La IA puede proponer una elección, pero no puede saltarse restricciones deterministas ni inventar autoridad. |
| **e) Catálogo tolerante por perfil** | Marcar como no seleccionable al perfil con descriptor desactualizado, reportarlo y conservar los demás perfiles válidos del canal. | Una falla puntual no debería detener trabajos de especialidades o canales que siguen listos. |

**Ejemplo:** dos perfiles declaran `BACKEND`: uno general y uno especializado en Spring. Ambos llegan como candidatos; la IA puede responder `SELECTED` para uno de ellos o `AMBIGUOUS` si necesita aclaración. Un perfil cuyo código incluye «BACKEND», pero tiene declarada el área `FRONTEND`, no aparece para un lote Java.

## 3. Qué NO cambia

- Las **7 funciones originales** usadas como referencia siguen intactas en `original/`. La propuesta todavía no modifica el selector productivo.
- Se respeta `DO_NOT_PRESELECT_BY_KEYWORD_OR_PROFILE_NAME`: el área limita candidatos, **no escoge por nombre** ni sustituye la decisión semántica.
- No se conceden permisos nuevos de escritura, ejecución, enrutamiento, publicación o modificación. La selección no autoriza efectos.
- No se crean perfiles programadores reales, no se activa ningún Worker y no se modifican Supabase, `main`, Análisis ni Testing.

## 4. Evidencia del experimento

**Base del PR #3666:** `d675a7248ac686049623c7f2c0906504bdfb6f34` (PR draft #3550).  
**HEAD de paridad inicial:** `8769970d254ccaf52f3d487f3dee10dbb1f40329`.  
**HEAD de primera versión experimental:** `b1d462450de680b1e0e3294a22be7391a7c49b6d`.  
**HEAD de correcciones de diseño evaluado por Claude:** `105ce43ad95e16a6bd1a67b10866d1d11c2cd86d`.

Resultados informados por **Claude**, en PostgreSQL 16 local desechable:

- En la paridad inicial: **6/6 salidas** originales coincidentes, **7/7 validaciones**, **3/3 protecciones**, **0 residuos**.
- Primera versión experimental: `test_experimental.py` **PASS (28 líneas PASS)** y `test_parity.py` **PASS** en base fresca.
- Con ambas correcciones de diseño: `test_experimental.py` **PASS (31 líneas PASS)**; incluye dos candidatos backend con `SELECTED` y `AMBIGUOUS`, exclusión del perfil de nombre engañoso, dos proyectos sin fuga de reglas y bloqueo de solicitudes cuando cambia la política. `test_parity.py` **PASS** en base fresca; **0 residuos**. Claude confirmó que `original/` y `test_parity.py` no cambiaron.

Los resultados anteriores son **verificaciones comunicadas por Claude**; este documento no afirma que ya exista despliegue ni adopción en el selector real. Código y comandos reproducibles: `experimental/functions_exp.sql`, `experimental/area_policy_exp.sql`, `experimental/seed_profiles_exp.sql`, `tests/test_experimental.py` y `experimental/STEP3_RUNBOOK.md`.

## 5. Decisiones pendientes de Cristhian

1. **¿Dónde declarar las áreas?** ¿Se amplía `lf_profile_selector_policy_v1` o se mantiene una tabla aparte, con gobernanza propia?
2. **¿Dónde viven las rutas de cada proyecto?** ¿En una tabla de configuración gobernada, un catálogo versionado o algún registro existente?
3. **¿Aceptas un catálogo tolerante por perfil?** Es decir, bloquear solamente el perfil desactualizado, con aviso visible, en lugar de bloquear toda la preparación.

**Siguiente paso propuesto:** revisar estas tres decisiones y, solo con tu conformidad, diseñar un PR separado contra **tu selector**. Mantener #3666 como evidencia experimental, sin fusionar ni copiar las funciones `_exp_` a producción automáticamente.
