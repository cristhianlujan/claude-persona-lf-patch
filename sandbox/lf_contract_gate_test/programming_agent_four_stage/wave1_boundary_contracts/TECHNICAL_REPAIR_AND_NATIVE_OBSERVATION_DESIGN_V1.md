# Reparaciones técnicas y observación Native — candidato, 27-oct-2026

Estado: SOURCE_ONLY_DESIGN_CANDIDATE. No crea autoridad, operación, proveedor,
perfil, grant, tabla, hook instalado ni activación. P1 e I0 siguen abiertos.

## Alcance autorizado y plan de validación

Tres entregas: corregir el retorno V2 en #3176; definir el encaje de una
reparación de BD en el Router nuevo; elegir un punto de observación Native.
La corrección SQL se mantiene en #3176. Este candidato contiene diseño,
adaptador puro de metadatos y pruebas sintéticas. Composición SQL local con
migraciones reales y catálogos sintéticos, separada de toda evidencia operacional.

## 1. Encaje propuesto de una reparación técnica

ACT-0001 Stage1 V2 clasifica PROGRAMACION/LF con alcance FUNCTION o CAPABILITY
aún UNRESOLVED. Stage2 deriva a selección semántica de perfil CURRENT.
Gate2 autoriza EJECUCION_PERFIL_LF en lectura; no admite la reparación.
El perfil investiga la fuente y devuelve especificación técnica. Antes del
primer efecto técnico se exige definición exacta, currentness y la admisión
aplicable. La aplicación de funciones/ACL sigue ACTUALIZACION_DB_LF, PR, PASE y
Merge Train; el Train reserva su ejecución. No hay escritura Supabase por chat.

Caso: public.fn_lf_decision_context_asof_record_v1(jsonb,text).
Delta propuesto: retirar EXECUTE a PUBLIC/anon/authenticated, conservar el
acceso autorizado del servicio; no cambiar payload, almacenamiento ni resolver.
El delta sigue siendo candidato hasta tener autoridad y revisar consumidores.

La admisión V2 actual NO cubre este destino: #3181 solo resuelve
lf-screen-contract://SHELL/MODULE/SCREEN y #3193 exige selección de pantalla.
No usar una pantalla ficticia, omitir la selección ni traducir una función
a una referencia de pantalla para obtener admisión.

Propuesta pendiente de decisión: contrato de definición técnica separado y
una versión futura de admisión discriminada por definition_kind.
Mantener SCREEN con su proveedor y selección actuales; TECHNICAL_ASSET requiere
un proveedor gobernado de identidad/currentness y un escritor que verifique
esa misma familia de sujeto. No modificar V1/V2 ni ampliar #3193 en este lote.

Material mínimo para revisar ese proveedor:

| Material | Requisito |
|---|---|
| Identidad | Proyecto, esquema y firma exacta de función; tipo técnico explícito |
| Fuente y revisión | Ref canónica gobernada, implementación Git fijada y readback DB |
| Estado observado | Huella del cuerpo y ACL normalizada y ordenada por rol/privilegio |
| Delta | Privilegios exactos antes/después; scope permitido y prohibido |
| Autoridad | Aprobación verificable del delta ligada al sujeto; una huella sola no basta |
| Vigencia | Relectura exacta cuerpo/ACL/dependencias y rechazo ante deriva |
| A9 y juez | Snapshot, scopes, pruebas negativas y juez independiente del mismo sujeto |
| Transporte | Migración Git-first y Train, con readback y rollback definidos |

Hasta admitir ese proveedor, el caso técnico queda
TECHNICAL_DEFINITION_PROVIDER_NOT_ADMITTED (diagnóstico propuesto, no código DB
instalado). Las pruebas locales de #3176 pueden continuar sin promoverlo.
El futuro proveedor debe reutilizar CURRENTNESS_AUTHORITY y los resolvers
gobernados existentes; no se propone otra tabla de snapshots.

Decisiones abiertas: contrato/familia técnica; aprobador y fuente canónica;
alcance de rollback de ACL; perfiles que pueden emitir A9 técnico; contrato
del escritor para sujetos que no sean pantalla. No se presupone decisión de
Cristhian ni se convierte este documento en autorización.

## 2. Punto elegido para observación GPT Native

El registro del productor lf_profile_native_bridge_record_output_v1 se detiene
en NATIVE_PRODUCER_VALIDATED (9/11): aún faltan semantic_judge y report_output.
Por eso ese registro no es el punto de completion.

Punto candidato: llamador/orquestador Native, después de que report_output
quede STEP_PASS_WITH_EVIDENCE y la ejecución EJECUCION_PERFIL_LF quede COMPLETED,
ambos confirmados mediante readback autorizado. Conservar la respuesta de
continuación calculada por lf_profile_result_router_return_prepare_v1; emitir
solo un aviso advisory independiente. La observación no decide esa continuación.

El adaptador puro native_completion_shadow_boundary_v1.py acepta la proyección
de la ejecución, los pasos terminales y un pin de contexto configurado por
fuente confiable. Verifica ejecución/perfil/canal/GPT_NATIVE y los dos pasos.
No deriva context_id/hash del modelo. No copia RAW, secretos o manifests al aviso.
No valida hashes JSONB ni sustituye la autenticación del readback: eso sigue
siendo responsabilidad del llamador y del caller RO existente.

La capa de dispatch futura reutilizará el aislamiento, cuota y timeouts del
observador #3148; no otro worker. Falta adaptar explícitamente ese contrato de
aviso al dispatcher existente y probar la combinación. Por ahora no hay dispatch.
enabled=false por defecto. Fallo de observación nunca modifica report_output,
COMPLETED, respuesta, resultado de PG-01 ni ruta del pedido.

## 3. Composición y límites

Separar dos pruebas:
- SQL local: D7 real + lector V2 + escritor runtime + compuerta corregida;
  entradas/catálogos/juez son sintéticos. Nunca constituye positivo A9 real.
- Native: proyección sintética COMPLETED + pasos terminales -> aviso advisory;
  estado prematuro, ejecución ajena, paso fallido y activación inválida -> omisión.

No se ejecuta GPT Native, IG, modelos, HTTP, escritor hosted ni migración hosted.
No se conecta este adaptador al bridge activo. Faltan el productor A9 admitido,
la revisión independiente, la seguridad de as-of, el proveedor técnico y el
llamador operacional. Las pruebas de composición no cierran P1, PR2 o I0.

## Checkpoints de este lote

| Punto | Entrega | Cierre que NO acredita |
|---|---|---|
| Retorno #3176 | Código V2 exacto y regresión con lectores reales | Despliegue, admisión operacional |
| Reparación técnica | Diseño explícito de sujeto/proveedor y decisiones pendientes | Proveedor admitido |
| Native | Punto posterior a report_output y adaptador puro apagado | Hook instalado o aislamiento de runtime |
| Composición | SQL local y pruebas sintéticas de límite Native | Recorrido real A9 a desarrollo |

## Evidencia local de este lote

- PostgreSQL 14.24 desechable, solo socket Unix; sin instalación global ni TCP.
- #3176: 20 casos existentes y prueba con lectores reales ampliada satisfactorios.
  La regresión nueva falla con el código anterior y pasa con el corregido.
- Escritor runtime #3193: regresión 21/21 satisfactoria.
- Composición: 7 grupos satisfactorios con D7, lector V2, escritor, retorno
  #3180 y compuerta reales. Ausencia retorna a Análisis; registro/replay conserva
  identidad; candidato no activa; ACTIVE solo dentro de ROLLBACK admite sin
  ejecutar; deriva de vigencia bloquea; destino técnico sigue no soportado.
- El recibo de autoridad terminal de perfil, el juez, el snapshot y el catálogo
  son fixtures explícitas. Esta corrida NO prueba 11/11 de una ejecución real.
- Adaptador Native: 10 pruebas unitarias satisfactorias, sin dispatcher instalado.
- PostgreSQL 17 objetivo, prueba con modelo real, llamador Native desplegado y
  positivo A9 admitido siguen pendientes. No se atribuyen estos resultados al CI.

Reproducción: ejecutar build_pg01_candidate_composition_v1.py con --repo-root
apuntando al repositorio que contiene los commits fijados, --gate-root al
checkout corregido de #3176 y --output a un directorio nuevo. El generador
no conecta a BD: produce composition.sql, migraciones exactas y sources.json.
Desde ese directorio ejecutar psql -X -v ON_ERROR_STOP=1 -f composition.sql
contra una BD exclusivamente desechable. El script termina con ROLLBACK.

## Cross-origin regression audit (2026-10-27)

The composition now includes a second completed execution with the same valid
Router binding. It cannot borrow the first execution's real accepted receipt:
the corrected #3176 entry rejects the producer/source mismatch. The positive
same-origin admission still succeeds only under the test-local ACTIVE toggle,
with downstream execution disabled. Eight composition groups now cover this
boundary. The generator pins the corrected gate hash; stale gate bytes fail
before materializing the composition.
