> Evidencia histórica del 24-oct. Para el estado separado del 26-oct, ver A6_A9_OBSERVER_FREEZE_V1.md; no atribuir 330 tests a esta rama actual.

# Factoría y paquete fuente A6/A9 · candidato sin despliegue

Estado: SOURCE_ONLY_DRAFT. Complementa A6_A9_COMPLETION_HOOK_V1.md.
No corrige ni califica el motor completo. Sin instalación, activación, conexión
hosted del driver, ejecución de perfiles/modelos o escritura en Supabase.

## Compatibilidad de base

main avanzó de 33684cc36 a 9b4a17406d8d356a298587939a29270349af7496 por #3149,
catálogo determinista de descriptores de perfiles del Router. Solo añadió
supabase/migrations/20261024224500_lf_profile_selector_descriptors_v1.sql.
Se conserva su blob íntegro en el merge local y en el candidato; no forma parte
del diff del PR respecto del nuevo main y no se vuelve a aplicar.
No cambia el hook, transporte ni la causa de los seis fallos observados.

## Diagnóstico de los seis fallos

Cinco fallos en test_engine no son fixtures desactualizadas. El motor invoca
execute_profile_runtime del runner genérico, cuyo build_runtime_request no
incluye executor_mode. PersistentLlamaServerAdapter exige REMOTE_API y rechaza
el request antes del cliente de inferencia con LLAMA_EXECUTOR_MODE_INVALID,
expected=REMOTE_API;observed=None. Afecta los caminos de execute y queue_execute,
así como batch y artifact_set que reutilizan esos caminos.
Los módulos en main actual mantienen el mismo contenido que en la base previa.
No se afirma que el servicio desplegado haya fallado: se reprodujo en código
local usando FakeLlamaClient, sin invocar el runtime ni modelos activos.

El sexto error de test_generic_profile_runtime_binding sí es una fixture
incompleta: declara model_context sin required_source_refs ni
allow_additional_sources; profile_model_sources la rechaza primero con
PROFILE_RUNTIME_REQUIRED_SOURCE_CONTRACT_INVALID.

No se quita el guard de executor_mode, no se inventa un contrato gobernado y no
se cambia una expectativa a FAIL para esconder el defecto. El runner de
contract_bound_profile_runtime.py ya inserta el modo desde execution_contract
antes de calcular el request_sha256 y valida identidad del adaptador y
atestación. Ese contrato y su procedencia deben formar parte de una corrección
acotada del motor; no basta con añadir el modo dentro del adaptador después de
hashear el request. Quedan pendientes el diseño/revisión del binding gobernado
y la corrección de la fixture con negativos de fuentes ausentes/extras.
Esto bloquea la calificación del productor, pero permite preparar en fuente el
observador de snapshots ya persistidos, sin ejecutar el productor.

## Factoría explícita

analysis_a6_a9_app_factory_v1.create_a6_a9_app(settings, config=None,
connection=None, engine_factory=None) compone el create_app existente.
Sin config usa enabled=false, sin construir transporte ni inyectar callback.
Config inválida se rechaza antes de construir app/transporte. Config habilitada
requiere conexión explícita y bindings válidos; construir la factoría no abre
conexiones, inicializa el motor o llama a modelos. La inicialización ordinaria
continúa perteneciendo al lifespan existente cuando un despliegue autorizado
lo arranque.

La factoría no es el entrypoint predeterminado, no lee env/archivos, no configura
systemd y no cambia install.sh. El proceso debe recibir config/secretos ya
aprobados desde su composición gobernada; enabled=true no concede autoridad.
El paquete mantiene las rutas del repo; el import path requerido para una
composición explícita incluye services/profile_runtime_api y la carpeta
wave1_boundary_contracts del release exacto. Nunca usar el worktree mutable,
PYTHONPATH de usuario o una ruta procedente de una solicitud como autoridad.
La factoría no se conecta automáticamente al servicio instalado.

## Paquete fuente reproducible

build_a6_a9_shadow_candidate_v1.py requiere repo, commit exacto de 40 hex y una
carpeta de salida fuera del repo. Usa git archive sobre objetos committed, no
tar del worktree. No fetch, pip, sudo, symlink de release, systemctl o scripts
de instalación. Nunca importa/ejecuta perfiles empaquetados.

Produce <commit>.tar y <commit>.manifest.json. El manifest liga commit/tree,
SHA-256 y tamaño del archivo y cada fichero exportado. Rechaza symlinks,
submódulos, miembros especiales, paths inseguros, inventarios incompletos y
transformaciones export-subst/export-ignore que alteren los bytes exportados.
Coteja todos los miembros con git show y verifica ambos outputs después de
escribir. Rechaza sobrescribir artefactos existentes. Solo empaqueta fuente
versionada; credenciales/untracked y modificaciones del worktree quedan fuera.
No es una auditoría de secretos previamente versionados ni un release admitido.
El manifest mantiene deployment_allowed=false, operational_admission=false y
model_execution_allowed=false. Llevar código SQL en el archivo no lo aplica.

## Pruebas y siguiente checkpoint

129 tests únicos locales satisfactorios: 121 del alcance anterior y 8 nuevos
(4 factoría y 4 empaquetado). Incluye default-off sin transporte, config inválida,
conexión explícita, composición sin inferencia/conexión, reproducibilidad,
exclusión de secretos untracked/worktree dirty, no overwrite y rechazo de links.
El grupo ampliado sigue con los seis fallos diagnosticados; no se declara verde.
La regresión A9 y los hashes de módulos concurrentes se verifican por separado.

Falta corregir/revisar el binding de ejecución del motor y la fixture, admitir
rol/target/TLS/ubicación de secreto y bindings reales, y ensayar el driver en
entorno aprobado. No se considera el smoke previo por exportación como ensayo
del nuevo driver. La activación operativa sigue separada y pendiente.
PG-01/P1/I0, C4/C7, D5/D7, positivo real y revisión independiente siguen abiertos.
