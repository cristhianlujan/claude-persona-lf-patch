# Profile Runtime Harness

Estado: `CANDIDATO_READ_ONLY / NO_HABILITADO_PARA_PRODUCCION`

## Objetivo

Ejecutar perfiles reales con una entrada fresca y conservar evidencia de lo que el
modelo/agente respondió antes de validar, juzgar o comparar. Este runtime elimina
la ambigüedad de los `run_cases.py` que construyen fixtures y luego validan su
propia salida esperada.

Regla principal:

```text
request real
→ cargar perfil/contratos/adapters
→ resolver contexto canónico
→ invocar executor real
→ CAPTURAR RAW
→ parsear
→ validadores determinísticos
→ semantic judge
→ comparar DIRECT vs ROUTER
→ receipt
```

## Lo que este harness no hace

- no fabrica respuestas esperadas;
- no usa fixtures como evidencia behavioral;
- no convierte un test estructural en prueba de comportamiento;
- no habilita runtime/producción;
- no escribe Supabase;
- no toma Drive como autoridad canónica;
- no ata el repositorio a OpenAI, Anthropic u otro proveedor.

## Executor real

El modelo se conecta mediante un contrato de proceso stdin/stdout. Configurar:

```bash
export PROFILE_RUNTIME_EXECUTOR='mi-runtime-de-modelo --json-stdin'
```

El comando recibe un único JSON `PROFILE_RUNTIME_EXECUTOR_V1` por stdin y debe
emitir exactamente un objeto JSON por stdout. El harness guarda stdout **antes**
de parsearlo.

Esto permite conectar Claude Code, un worker propio, un servicio OpenAI, un
orquestador interno u otro motor sin cambiar los perfiles.

Si no existe `PROFILE_RUNTIME_EXECUTOR`, el resultado obligatorio es:

```text
BLOCKED
behavioral_evidence_eligible=false
fixture_output_used=false
```

## Contexto canónico

Dos modos:

1. `PROFILE_RUNTIME_CONTEXT_RESOLVER`: proceso externo que resuelve la fuente
   canónica y devuelve `canonical_context` + `source_refs`.
2. Passthrough controlado: el request ya trae `canonical_context` y
   `canonical_source_refs`.

Para LF, la autoridad esperada es Supabase. El passthrough permite que el Router
u orquestador que ya tiene acceso canónico prepare el contexto sin duplicar
credenciales dentro de este harness.

## Directo vs Router

`--activation-path BOTH` ejecuta dos llamadas independientes con la misma
solicitud y contexto:

- `DIRECT`;
- `ROUTER`.

La versión Router recibe únicamente el contexto de enrutamiento declarado en el
manifest. Después se comparan:

- `deliverable_created.remediation_actions`;
- `shell_binding`, ignorando solo referencias de procedencia `router:*`.

Una divergencia material produce `FAIL`.

## Semantic judge

Cuando el manifest lo exige, el mismo executor recibe una segunda llamada con
`phase=SEMANTIC_JUDGE`, el judge independiente y las respuestas direct/Router.
El self-score del perfil no puede sustituir al judge.

## Evidencia

Cada ejecución conserva, como mínimo:

```text
input_direct.json
profile_execution_direct.raw.stdout.txt
profile_execution_direct.raw.stderr.txt
parsed_direct.json
input_router.json
profile_execution_router.raw.stdout.txt
profile_execution_router.raw.stderr.txt
parsed_router.json
validator_*.stdout.txt
validator_*.stderr.txt
input_semantic_judge.json
semantic_judge_*.raw.stdout.txt
semantic_judge.json
receipt.json
```

El receipt registra hashes del source pack y del comando executor, estado de
validadores, comparación Router/direct y elegibilidad de evidencia.

## Primer perfil conectado

`profile_runtime/manifests/ui_architect.json`

Carga:

- `profiles/ui_architect/SKILL.md`;
- contratos de Production UI Spec / LF / missing inputs / existing screen;
- schema de producción;
- `lf_shell_profile_adapter`;
- validator determinístico;
- semantic judge;
- ruta Router `ACT-0001 -> EJECUCION_PERFIL_LF -> PERFIL-UI-ARCHITECT`.

## Canary

Ejemplo:

```bash
python3 profile_runtime/runner.py \
  --manifest profile_runtime/manifests/ui_architect.json \
  --request profile_runtime/examples/ui_architect_checkout_canary_request.json \
  --activation-path BOTH \
  --output-dir /tmp/ui-architect-runtime-canary
```

Sin executor real, debe bloquear. Con executor real, el cierre válido requiere:

```text
deterministic_validator_pass=true
semantic_judge_pass=true
direct_router_consistency_pass=true
status=PASS_WITH_EVIDENCE
behavioral_evidence_eligible=true
```

## Test del harness

`profile_runtime/tests/test_harness.py` usa un executor sintético únicamente para
verificar transporte, captura RAW y fail-closed del runtime. Ese test nunca debe
ser citado como prueba behavioral de `ui_architect`.
