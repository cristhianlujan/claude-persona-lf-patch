# Motor de Aprendizaje — independent test boundary

Estado: SANDBOX_ONLY / NO_PRODUCTION / NO_AUTO_IMPACT

## Objetivo

Permitir que `MOTOR_DE_APRENDIZAJE` pruebe y corrija `ACT-0046` sin depender de implementaciones de S26, S28 o S30 y sin apilar PRs.

## Autoridad y fuentes

- Router: `ACT-0001`.
- Autoridad operativa: Supabase.
- Fuente operativa: `public.v_lf_fuente_operativa`.
- EKB: `transversal.error_knowledge` y reglas preventivas aplicables.
- Google Drive: solo bytes de soporte visual para `IMAGE_ASSET` previamente resuelto/bindeado en Supabase; nunca autoridad operativa.
- GitHub: artefactos técnicos y evidencia de implementación; nunca sustituye el estado operativo de Supabase.

## Frontera de independencia

El loop unitario del Motor puede avanzar de forma autónoma hasta `PRUEBA_SANDBOX`:

`DETECTADO -> ANALIZADO -> CARD_CREADA -> EN_REVISION -> PRUEBA_SANDBOX`

No requiere S30 para descubrir, analizar, atribuir, puntuar, proponer y probar una mejora candidata. S30 entra después, usando exactamente el mismo caso congelado, para gobernar promoción/impacto y medir efectividad.

Los estados posteriores permanecen como gate de integración:

`APROBADO -> IMPACTADO -> VERIFICADO -> CERRADO`

## Dependencias prohibidas en el loop unitario

- importar/copiar implementación de S26, S28 o S30;
- depender de una rama o PR abierto;
- copiar migraciones desde otro carril;
- modificar `.github/**` para acelerar este loop;
- considerar un Deep CI compartido como evidencia semántica del Motor;
- usar Drive/Docs como fuente del contenido operativo.

## Estrategia de pruebas

Cada caso conserva `input.json` y `output.json` literales. Durante iteración se usa un gate local/determinista del propio caso. Los Deep Gates compartidos son calificación de integración/merge, no dependencia para seguir desarrollando el Motor.

Antes de merge, el candidato debe volver a pasar la validación transversal exact-head vigente. Esto evita crear una segunda implementación de Shared Assurance mientras elimina el bloqueo circular de desarrollo.

## Regla de PR

Cada PR del Motor nace desde `main` vigente y posee paths exclusivos. No stacking entre PRs abiertos. Si una unidad necesita un cambio de otra, espera que ese cambio llegue a `main`; mientras tanto continúa con casos independientes que no requieran esa dependencia.
