# QA Mockup Visual Bug Hunt

## Objetivo

Detectar mockups genericos o que no respetan la marca del proyecto.

## Revisar por pantalla

- ¿usa frame de app?
- ¿usa marca correcta?
- ¿usa tokens del proyecto?
- ¿respeta progreso y header_policy?
- ¿respeta layout_sections?
- ¿evita blocked_visual_patterns?
- ¿muestra errores/estados cuando son relevantes?
- ¿se ve como producto real y no como diagrama?

## Veredictos

- PASS_CANDIDATO_READ_ONLY
- PASS_WITH_OBSERVATIONS
- RETURN_TO_WORKER
- FAIL_BRAND_MISMATCH
- FAIL_GENERIC_MOCKUP
- BLOCKED_SOURCE_MISSING

## Fail inmediato

- colores inventados;
- mockup sin frame;
- no leer tokens;
- no leer screen_visual_specs;
- pantalla clave representada solo como tabla;
- no renderizar visualmente.
