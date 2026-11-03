# LF — PE10A_SR03 / SR04 | Llamada del Reparador a la habilidad Profile Updater

**Estado:** candidato, sin enforcement server-side ni E2E. **Alcance exacto:** habilidad Profile Updater (entrada, ejecución interna y respuesta). Router ACT-0001 y encaminamiento del perfil quedan FUERA DE ALCANCE.

## Flujo aprobado

```text
Router ACT-0001 (encaminamiento existente, no tocar)
  -> Perfil Reparador LF (ya ejecutándose)
     -> LLAMADA a habilidad PROFILE_UPDATER
        -> habilidad recibe y valida solicitud
        -> habilidad ejecuta autónomamente sus 17 etapas y su motor GitHub/OIDC + Edge/RPC
        -> habilidad devuelve RAW + estado + evidencias/recibos + siguiente acción
     <- Perfil Reparador recibe, valida, registra y continúa en el MISMO run
```

**La habilidad es dueña de su ejecución.** GitHub Actions, Edge y RPC son implementación interna de Updater. No se introduce un Router B, un orquestador externo adicional, ni se altera ACT-0001. El Reparador no ejecuta el Updater etapa por etapa: realiza una llamada y procesa la respuesta recibida.

## Entradas / proceso / salidas

| Frontera | Productor / consumidor | Contrato mínimo y comprobación |
| --- | --- | --- |
| Solicitud | Reparador -> habilidad | Run del Reparador, identidad de perfil, solicitud, diagnóstico probado, target exacto, scope y referencias de autoridad/política |
| Admisión | Habilidad | Releer run padre y evidencia SERVER-SIDE; comprobar que existe decisión de actualización válida, que el scope coincide y que el padre está activo |
| Motor interno | Habilidad Updater | Reutilizar `ACTUALIZACION_PERFIL_LF`, 17 etapas, GitHub Actions/OIDC + Edge/RPC y ledger propios; el Reparador no sustituye el motor |
| Respuesta | Habilidad -> Reparador | `source_execution_id`, `child_execution_id`, estado, RAW/referencia, evidence refs, SHA de recibo y HEAD, siguiente acción |
| Recepción | Reparador | Validar vínculo hijo/padre y recibo real; registrar respuesta y continuar en el MISMO run; en SRCR actual antes de `report_output(80)` |

La condición de paso SRCR vigente es diagnóstico real `execute_profile(50)`, `output_validate(60)`, `semantic_judge(70)` y retorno antes de `report_output(80)`. **Estos números describen el perfil SRCR actual, no un contrato transversal que imponga numeración a otros perfiles.**

## Reutilización de IG (solo el patrón)

IG: perfil solicita -> IG ejecuta internamente -> IG devuelve al perfil. Updater: Reparador solicita -> habilidad Updater ejecuta internamente -> Updater devuelve al Reparador.

NO copiar `CONTEXT_PACK`, `consumer=PROFILE_EXECUTION` o `resume_via` como campos normativos del Updater. Son detalles de la implementación IG; su ticket no autoriza escrituras GitHub.

## Evidencia y bloqueo

PR candidato #3520 incluye contrato tipado, validador fail-closed y pruebas estructurales. **No** implementa aún la conexión real del perfil con la habilidad, validación servidor de la invocación ni la recepción terminal; no afirmar PASS, no cerrar SR03/SR04/ST12/OP08 y no merge sin prueba E2E.

El controlador de habilidad debe rechazar: run padre inexistente o terminal, falta de diagnóstico, origen SALY, target incorrecto, path no canónico, SHA/scope obsoleto, autorización autodeclarada, respuesta no correlacionada y recibo inexistente. Un JSON de prueba o un PASE de CI no reemplaza recibo LIVE.

**Siguiente lote:** implementar SOLAMENTE la función/adaptador de entrada y salida de Profile Updater usando su motor actual. Sin cambios en Router, permisos globales, motor de IG o servicio de orquestación genérico.
