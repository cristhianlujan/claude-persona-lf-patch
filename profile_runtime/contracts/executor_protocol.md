# Executor Protocol — PROFILE_RUNTIME_EXECUTOR_V1

## Propósito

Desacoplar el harness del proveedor/modelo sin perder evidencia RAW.

## Entrada

El executor lee un único JSON desde stdin.

### PROFILE_EXECUTION

Campos principales:

- `runtime_contract = PROFILE_RUNTIME_EXECUTOR_V1`
- `phase = PROFILE_EXECUTION`
- `activation_path = DIRECT|ROUTER`
- `profile`
- `router_context`
- `request`
- `canonical_context`
- `canonical_source_refs`
- `source_pack[]`
- `executor_rules`

`source_pack[]` incluye `path`, `sha256` y `content` de los archivos que el perfil
debe consumir para esa ejecución.

### SEMANTIC_JUDGE

Campos principales:

- `phase = SEMANTIC_JUDGE`
- `judge_source`
- `direct_output`
- `router_output`
- request y contexto canónico idénticos al run evaluado.

## Salida

stdout debe contener exactamente un objeto JSON UTF-8, sin Markdown fences,
prefacios ni texto posterior.

stderr puede contener logs operativos. El harness lo preserva como evidencia,
pero nunca lo mezcla con el output del perfil.

## Códigos de salida

- `0`: el executor produjo una salida candidata;
- cualquier otro código: ejecución fallida.

Un exit `0` no implica PASS. El output todavía debe atravesar parser, validator,
semantic judge y comparación Router/direct.

## Requisitos behavioral

Un executor elegible para evidencia real debe:

1. invocar realmente un modelo/agente;
2. usar el `source_pack` entregado en esa ejecución;
3. no seleccionar una respuesta preconstruida por `case_id`;
4. no leer un archivo `expected_output` para devolverlo como respuesta;
5. permitir entradas frescas no conocidas al construir el test;
6. devolver la respuesta antes de que los validators/judges decidan PASS/FAIL.

## Executors sintéticos

Se permiten únicamente para pruebas del transporte del harness. El receipt o
test que use uno debe marcarse como ingeniería del runtime y no puede probar la
calidad/comportamiento de un perfil.

## Seguridad

El harness usa `subprocess.run()` sin `shell=True` y tokeniza el comando con
`shlex.split`. Las credenciales del proveedor pertenecen al executor o a su
entorno; no deben persistirse en manifests, requests ni source packs.
