# Conexión opcional A6/A9 después de completar jobs · candidato v1

Estado: SOURCE_ONLY_DRAFT. No instalado ni activado. Revisión independiente pendiente.
Este incremento amplía #3148; no aplica el receptor SQL de #3135.

## Punto de conexión existente

create_app admite completion_observer=None. El worker conserva la ejecución y
store.complete originales. Solo en el else de ese try notifica metadatos mediante
CompletionObservation, con un catch separado que nunca llama store.fail.
No se añade endpoint ni se modifica el contrato de requests, respuestas o SQLite.
Reintentos idempotentes reutilizan el job y no repiten la observación. Los jobs
FAILED no notifican. COMPLETED significa persistencia del resultado del runtime;
no significa éxito semántico del perfil o producción de un A9 válido.

La observación recibe únicamente job_id, kind, request_id, request_sha256 y una
tupla de perfil único. No recibe resultado, literal, imagen, credenciales, store
ni payload. Su retorno no se usa para controlar ruta o estado.
El dispatch arranca un daemon con cupo por app de dos, sin cola ni espera.
Error de arranque/callback o cupo agotado no reemplazan el resultado.
El arranque tiene coste; no se afirma latencia cero ni calificación bajo carga.
Threads no son un sandbox de seguridad para código hostil. Un callback colgado
ocupa su cupo hasta terminar; no se crean hilos sin límite ni se mata el proceso
principal para recuperarlo. close impide nuevas observaciones y no espera a las
existentes. El diagnóstico puede perderse al apagar el servicio.

## Binding y configuración

A6A9CompletionObserver.from_config(config, read_one) recibe configuración trusted
explícita. No carga archivos o variables de entorno automáticamente. La plantilla
analysis_a6_a9_completion_shadow_disabled_v1.json tiene enabled=false y bindings=[].
No se instala una factoría, job, timer o unidad systemd en esta propuesta.

Cada binding requiere request_id, request_sha256, kind y expected con los cinco
campos de ExpectedContext. request_sha256 es el hash canónico de la solicitud
validada/renderizada por el runtime (model_dump(mode="json", by_alias=True)),
no un hash proporcionado por el modelo. El perfil debe ser exactamente
PERFIL-PROGRAMMING-ANALYSIS-LF. kind admite execute, queue_execute o artifact_set_execute.
Máximo 64 bindings; duplicados o valores inválidos rechazan la configuración.
El contexto esperado se decide antes por una fuente trusted: consumidor, sujeto,
as-of UTC con zona, context_id y hash exactos. No se deduce de result, no busca
latest y no transforma el output de Análisis en un snapshot por inferencia.

El callback no crea A9: lee un snapshot ya persistido por su productor autorizado.
Si la persistencia aún no existe, UNKNOWN o mismatch quedan como diagnóstico y
no se reintenta. Cambiar el momento de persistencia requiere otro acuerdo.
Diagnósticos: anillo de memoria de 64 elementos, solo estado y flags de no efecto.
No se persisten ni se añaden a la respuesta pública. No son recibos PG-01.

## Transporte RO

PsycopgReadOne es callable para SqlReadPort. Solo admite READ_SQL y tres parámetros;
rechaza SQL arbitraria antes de conectar. Usa psycopg ya declarado en requirements.in.
Requiere host, dbname, user y password explícitos; port opcional, SSL verify-full
por defecto (verify-ca también permitido). No hereda una DSN del servicio ni busca
credenciales. La ubicación del secreto, identidad/privilegios del rol, target y
certificado deben resolverse y calificarse antes de un despliegue autorizado.
No reutilizar un rol del servicio o de CI por conveniencia; esta propuesta no
concede acceso ni afirma que un rol específico ya esté admitido.

Fija connect_timeout=2, default_transaction_read_only=on, statement_timeout=1500 ms,
lock_timeout=500 ms e idle_in_transaction_session_timeout=2000 ms. Con autocommit=True,
abre BEGIN READ ONLY, ejecuta la SELECT fija parametrizada del caller y comprueba
el booleano RO del servidor. Rollback y close en finally, sin commit ni retry.
El caller conserva comprobación de contexto exacto y digest PostgreSQL.
RO no sustituye privilegios mínimos ni demuestra inocuidad de toda función del servidor.
Estos límites no constituyen un plazo de pared universal de DNS/red: la cuota
impide crecimiento ilimitado si un transporte queda colgado. Pendiente ensayo de
conexión real del driver con el rol/target/TLS autorizado y evaluación de carga.

## Composición propuesta, sin activación

Una factoría revisada de despliegue puede construir PsycopgReadOne con credenciales
RO aprobadas, parsear la configuración explícita e inyectar el observer mediante
create_app(settings, completion_observer=observer). Los módulos A6/A9 deben estar
presentes en el release con su ruta de import revisada. No se modifica sys.path en
el servicio ni se añade carga dinámica desde rutas suministradas por usuarios.
El entrypoint actual sigue creando app sin observer: apagado por defecto.
Un despliegue debe incluir factoría y empaquetado explícitos, rollback de release,
ensayo RO, binding trusted y observación de recursos. No se activan aquí.

La consulta Router con el literal de confirmación queda unresolved; no es
una autorización de actualización/ejecución del runtime. Se conserva el alcance
autorizado de desarrollo de candidato en draft; sin efecto oficial ni cierre.

## Evidencia y límites

121 tests únicos locales satisfactorios: 25 nuevos (15 transporte/binding y
10 dispatcher/API), 60 A6/A9 existentes y 36 regresiones del runtime.
Regresión A9: positivo payload + positivo assembler + 2 negativos assembler +
14 negativos payload, satisfactoria en local.
API→callback→caller probado in-process con motor y read port sintéticos; sin
llamadas a modelos, ejecución de perfiles o jobs del servicio activo.
El driver usa un conector DB-API fake en pruebas; no hubo un nuevo smoke hosted.
El smoke RO real anterior de #3148 no prueba este nuevo driver.

La ampliación a 132 pruebas encontró 5 failures y 1 error en test_engine y
test_generic_profile_runtime_binding. Los mismos seis fallos se reproducen en
las 11 pruebas de esos módulos sobre main intacto 33684cc36. Se conservan sin
modificar en este PR; la regresión ampliada no está verde y esto no califica
el motor completo ni el despliegue.
Evidencia: analysis_a6_a9_completion_hook_local_20261024.json.
Sin apply, merge, ready-to-merge, cambios de perfil/workflow/migración, escritura
hosted, nueva obligatoriedad ni cierre PG-01/P1/I0. C4/C7, D5/D7 y positivo A9 siguen pendientes.
