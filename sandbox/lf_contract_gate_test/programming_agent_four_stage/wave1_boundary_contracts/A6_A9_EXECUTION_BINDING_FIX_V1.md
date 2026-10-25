# Corrección del binding de ejecución del motor · candidato v1

Estado: SOURCE_ONLY_DRAFT. No instalado o activado. Revisión independiente pendiente.
Esta sección sustituye el estado de fallos de A6_A9_FULL_REVIEW_V1.md para el
árbol nuevo; los resultados históricos permanecen con su alcance original.

## Problema y corrección

Cinco pruebas de test_engine fallaban porque el motor utilizaba el runner
genérico, cuyo request no incluye executor_mode, y el adaptador exige REMOTE_API.
Se conserva esa exigencia y se cambia la entrega del motor al wrapper existente
execute_contract_bound_profile_runtime. No se modifica llama.py, el runner
genérico, el wrapper o su registro de identidades para forzar una aprobación.

ProfileRuntimeEngine recibe execution_binding_provider por constructor, nunca
por la solicitud HTTP o la salida del modelo. El proveedor resuelve una
ResolvedExecutionBinding desde una fuente confiable y previamente admitida;
esta propuesta define el puerto de consumo, no admite ni instala ese proveedor.
El motor no construye el contrato: consume el recibido y coteja su hash con el
esperado independiente entregado por el proveedor, su firma de request, run_id,
profile_code, context_fingerprint y modo. Una copia JSON impide que cambios del
payload del proveedor modifiquen la versión consumida.

El descriptor liga request_id/execution_id, perfil/slug, digest literal de input,
fuentes normalizadas, adaptadores, fingerprint del contexto gobernado y modo.
El execution_id usa governed_operation.execution_id cuando existe; conserva el
identificador por request anterior cuando no existe. El contrato debe coincidir
con ese identificador; no se reemplaza silenciosamente para hacerlo pasar.
El proveedor es código confiable de composición, no sandbox de seguridad.
Su fuente, admisión y currentness deben verificarse externamente; un source_ref
o un hash por sí solos no demuestran autoridad operacional.

El wrapper canónico ya introduce el modo y el digest del contrato antes de
calcular request_sha256, valida el contrato, identidad del adaptador, proveedor,
modelo y atestación, y produce un recibo con hash consistente.
La evidencia de consumo se devuelve separada en runtime_completion.execution_binding;
no se altera el recibo canónico después de hashearlo. downstream_authorized
permanece false. No se cambian requests HTTP, SQLite o el observador opcional.

## Ausencia de contrato y tests

Sin proveedor, el motor retorna RUNTIME_EXECUTION_BINDING_REQUIRED antes de
health/inferencia. No vuelve al runner genérico, no inventa scope/política ni
usa fixtures como fallback. is_test_double debe declararse booleano; un proveedor
sintético se rechaza por defecto. Solo el constructor de tests permite
allow_test_execution_bindings=True, sin parámetro HTTP/env o autoactivación.
La factoría/deployment actual no suministra un proveedor operativo: sigue pendiente.

Los cinco positivos originales conservan sus expectativas; su fixture ahora
inyecta SyntheticExecutionBindingProvider marcado is_test_double=True, con
referencias fixture:// y contrato sintético explícito. El modelo fake se llama
fake-local-qwen-model para ejercitar también el registro de identidad existente;
no acredita inferencia, atestación operacional ni un proveedor real.

12 pruebas nuevas cubren contrato ausente en ambos caminos, test provider sin
opt-in, caída del proveedor sin fallback, digest alterado, binding de request
incorrecto/reutilizado con input diferente, run/perfil/contexto ajenos, modo
incorrecto, contrato estructural inválido, adaptador no registrado, hash del
request/recibo y modo atestado incorrecto. Los rechazos previos a modelo comprueban
que no hubo llamadas a health/chat. El positivo verifica modo/contrato/fuentes
incluidos en el hash y conserva el bloqueo downstream.

## Resultado y continuación

330 pruebas únicas locales: 242 del servicio completo + 88 del observador,
transporte y empaquetado. Cero failures/errors/skipped; unittest OK.
Regresión A9 separada: positivo payload/assembler + 2/14 negativos satisfactoria.
Los cinco fallos anteriores quedan corregidos en el recorrido con contrato válido;
la falta de contrato operativo sigue siendo un rechazo esperado, no habilitación.
No se usa comparador de fallos conocidos para declarar esta corrida verde.

Se intentó continuar con un ensayo real del driver en Postgres aislado, pero
no hay initdb/pg_ctl/postgres accesibles y Docker deniega acceso al socket.
No se cambian permisos, usan privilegios alternativos o credenciales del servicio.
No se ejecutó ese ensayo. Las pruebas del driver siguen siendo con conector fake;
el smoke previo por exportación no se convierte en prueba del driver.

main avanzó con #3151: conexión del flujo de Producto al selector dinámico de
perfiles. Su migración 20261025000500_lf_router_product_dynamic_profile_selection_v1.sql
se conserva desde main sin aplicación propia. #3149/#3150 permanecen intactos. La corrección no modifica el Router.

Pendientes: resolver/admitir el proveedor real del contrato, revisión independiente,
Postgres aislado/ensayo hosted RO aprobado, rol/target/TLS/secreto, bindings reales
y recursos. Mantener draft, default-off y sin despliegue; PG-01/P1/I0, positivo A9,
C4/C7 y D5/D7 abiertos. Sin merge, ready-to-merge, apply, modelos o escritura hosted.

## Siguiente ensayo preparado, sin ejecutarlo

run_a6_a9_ro_driver_smoke_v1.py recibe exclusivamente --connection-file y
--expected-file. Reutiliza PsycopgReadOne y el caller existente, sin ejecutar
perfiles o invocar modelos. La conexión debe ser previamente aprobada y su
archivo regular, sin symlink, propiedad del usuario ejecutor, sin permisos de
grupo/otros y de hasta 64 KiB. Se abre una sola vez con O_NOFOLLOW y se valida
el descriptor abierto antes de leer, sin TOCTOU de lstat/read_text.
Nunca lee una DSN del entorno ni muestra secretos o payloads. JSON de salida
solo con estado, id/hash esperado si se observó, y diagnóstico resumido.
UNKNOWN, mismatch, timeout o excepción no devuelven un smoke verificado; el
exit=0 solo identifica OBSERVED en ese ensayo, no admisión o cierre de PG-01.
Un RETURN_TO_ANALYSIS puede ser una lectura observada correcta de un histórico
incompleto y sigue sin ser positivo A9. Cinco pruebas sintéticas cubren query
exacta, conservación, mismatch/UNKNOWN, sanitización y archivo privado.
El ensayo real queda pendiente de un Postgres aislado o conexión RO admitida.
