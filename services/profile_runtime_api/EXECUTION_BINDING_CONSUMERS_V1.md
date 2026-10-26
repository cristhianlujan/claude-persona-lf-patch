# Consumidores del cambio compartido del motor · 26-oct-2026

Candidato separado para revisión de Cristhian. No desplegar ni activar.
Inventario de fuente en main 7e861f1fa4293e93a5a43fc352ef1250f11dd5af; no prueba del servicio vivo.
El constructor por defecto no tiene execution_binding_provider. Si se instala
este cambio sin proveedor, los cuatro recorridos de inferencia devuelven
RUNTIME_EXECUTION_BINDING_REQUIRED antes de health/modelo. HTTP 202/job COMPLETED
no demuestra éxito del perfil: el resultado interior estará rechazado.

| Consumidor / ruta | Efecto sin proveedor configurado |
|---|---|
| profile_runtime_api/__main__.py y app.py por defecto | Crean el motor sin proveedor; inicialización/health/runtime pueden funcionar, pero no la inferencia de los cuatro recorridos |
| POST /v1/profile/execute → run_execute | Resultado de perfil rechazado antes de modelo |
| POST /v1/profile/queue-execute → run_queue_execute | Resultado de perfil rechazado antes de modelo |
| POST /v1/profile/artifact-set-execute | Resultado de perfil rechazado al reutilizar _execute_profile |
| POST /v1/profile/batch | Cada perfil que alcanza inferencia queda rechazado; no se autoriza downstream |
| deploy/lf-profile-runtime-api.service | Su entrypoint estándar no inyecta proveedor; un despliegue sin composición nueva bloquearía esos recorridos |
| scripts/hetzner_queue_worker.py y deploy/lf-profile-runtime-queue-worker.service | Envía solicitudes a execute/queue-execute/artifact-set-execute; no aporta proveedor de constructor y recibe rechazo interior; el baseline previo puede completarse, pero la ejecución principal no |
| scripts/run_benchmark.py | Consume /v1/profile/batch; no puede obtener completions válidos con la composición estándar sin proveedor |
| .github/workflows/lf-router-level2-advisory-tests.yml | Revisión obligatoria: ejecuta tests del bridge del worker y consumidores semánticos con dobles. No llama al motor real por defecto; NO se afirma que ese workflow se rompa directamente. Sus tests no acreditan una operación real con proveedor |
| scripts/lf_runtime_independent_readback.py | Revisión obligatoria: verifica manifest de todos los archivos services/profile_runtime_api y hace readback de health/runtime/proceso. No ejecuta perfiles; NO se rompe directamente por ausencia de proveedor. Puede verificar un runtime sano que aun rechaza inferencia. Requiere hashes del nuevo release y no es calificación funcional |
| tests/test_engine.py | Positivos requieren proveedor sintético explícito y opt-in de tests; no es proveedor operativo |
| POST /v1/profile/research-baseline | No usa _execute_bound_runtime; esa generación no se bloquea directamente por este cambio. No concede permiso para la ejecución principal |
| GET /health, GET /runtime, GET /v1/jobs/{id} | No consumen este binding para generar; seguir accesibles no demuestra que execute funcione |
| Runner genérico/contract_bound fuera de este servicio | Sus fuentes no se modifican; no son consumidores directos del constructor nuevo |

No se ejecutó este readback, el worker, benchmark, perfiles/modelos ni los
workflows de ejecución operativa. Solo lectura de código y pruebas locales con
dobles. El inventario no afirma exhaustividad de clientes externos desconocidos.

## Decisión antes de activar

Cristhian debe revisar el alcance compartido, resolver una fuente gobernada real
del contrato y su entrega/admisión/currentness, y aprobar una composición que
inyecte el proveedor. La integración por defecto no lo inventa y no puede
habilitarse con un flag enviado por HTTP. Este documento deja el impacto
reviewable; no se envió ningún mensaje externo ni se declaró conocimiento/GO del owner.

Actualización de base: main ce3a96ba7bf25cc8ef4b1142509a5a6c6399a267 incorpora #3165 (workflow advisory y migración de contexto Producto). El workflow añade comprobación fuente de ese precheck; sigue sin invocar el motor real. El resto del inventario no cambia.
