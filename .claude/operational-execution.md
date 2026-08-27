# Protocolo operativo reutilizable para agentes

## Contenido

1. Propósito
2. Secuencia operativa
3. Contrato de entrada
4. Contrato de superficie
5. Formato Markdown seguro
6. Formatos machine-readable
7. Contenido literal
8. Escritura y readback
9. Validación determinista
10. Evidencia y estados
11. Delegación
12. Plantillas positivas
13. Ejemplos
14. Fuentes de diseño
15. Protocolo de pase para actualización de perfiles

## 1. Propósito

Aplicar una secuencia uniforme para crear, transformar, transportar y presentar
artefactos sin perder contenido, estructura, trazabilidad ni compatibilidad con
la superficie de destino.

Este protocolo complementa las instrucciones de dominio. El `SKILL.md`, los
schemas y los contratos específicos conservan autoridad sobre el contenido; este
archivo gobierna la ejecución.

## 2. Secuencia operativa

Ejecutar siempre este ciclo:

```text
RESOLVER
→ INSPECCIONAR
→ PLANIFICAR
→ CONSTRUIR
→ VALIDAR
→ PERSISTIR
→ RELEER
→ COMPARAR
→ REPORTAR
```

### RESOLVER

Confirmar:

- artefacto objetivo;
- fuente autorizada;
- versión de fuente;
- alcance de lectura;
- alcance de escritura;
- superficie de salida;
- formato esperado;
- criterio de cierre;
- evidencia requerida.

### INSPECCIONAR

Examinar antes de escribir:

- delimitadores ya presentes;
- bloques anidados;
- codificación;
- saltos de línea;
- schema o gramática;
- referencias internas;
- tamaño y conteos;
- archivos temporales existentes;
- instrucciones más específicas aplicables.

### PLANIFICAR

Definir:

- archivos que se crean o modifican;
- orden de operaciones;
- validaciones por archivo;
- readback requerido;
- criterio de rollback o bloqueo;
- datos que se reportarán al cierre.

### CONSTRUIR

Producir el cambio dentro del alcance resuelto, usando las convenciones del
artefacto y preservando información válida.

### VALIDAR

Ejecutar validaciones sintácticas, semánticas y de integridad antes de declarar
el artefacto listo.

### PERSISTIR

Escribir en el destino autorizado con la codificación y normalización definidas.

### RELEER

Leer el artefacto desde el destino real, no desde la copia de trabajo.

### COMPARAR

Comparar:

- SHA-256;
- bytes;
- líneas;
- inventario de archivos;
- campos o secciones obligatorias;
- resultado del parser o schema;
- referencias resolubles.

### REPORTAR

Emitir el estado real, la evidencia, las diferencias y el siguiente paso.

## 3. Contrato de entrada

Cada operación debe resolver como mínimo:

```yaml
operation_id: <ID>
artifact_path: <RUTA>
source_ref: <FUENTE>
source_version: <VERSION>
read_scope: []
write_scope: []
output_surface: FILE|CHAT|GITHUB|DATABASE|API
content_format: MARKDOWN|JSON|YAML|PYTHON|TEXT|OTHER
literal_required: true|false
expected_schema: <RUTA_O_NULL>
expected_sha256: <HASH_O_NULL>
expected_files: []
validation_commands: []
readback_required: true
```

Cuando falte un dato material, registrar el campo faltante y retornar `BLOCKED`
o `PENDING_DECISION` según el contrato de dominio.

## 4. Contrato de superficie

Adaptar la envoltura al destino sin alterar el contenido.

| Superficie | Aplicación |
|---|---|
| Archivo | Escribir contenido puro, sin envoltura conversacional |
| Chat | Seleccionar delimitadores que contengan de forma segura el contenido |
| GitHub | Escribir en rama autorizada y releer el blob resultante |
| Base de datos | Normalizar UTF-8/LF, calcular hash y releer la fila vigente |
| API | Cumplir schema, tipos, codificación y orden contractual |

Mantener separados:

```text
contenido del artefacto
envoltura de transporte
comentario explicativo
evidencia de ejecución
```

## 5. Formato Markdown seguro

### Regla de delimitadores

Antes de envolver Markdown completo en un bloque de código:

1. medir la secuencia más larga de backticks dentro del contenido;
2. medir la secuencia más larga de tildes dentro del contenido;
3. elegir el carácter con menor colisión;
4. usar una valla externa de longitud superior a cualquier secuencia interna;
5. conservar el contenido interno literalmente;
6. comprobar visualmente el inicio y el cierre.

Ejemplo:

```text
contenido interno contiene ```
→ usar ```` como delimitador externo
```

El validador calcula `recommended_markdown_wrapper`.

### Regla de bloques internos

Mantener cada bloque interno con su lenguaje original. Una envoltura externa más
larga permite conservarlos sin cerrar prematuramente la presentación.

### Regla de tablas

Para cada tabla:

- conservar la misma cantidad de columnas por fila;
- escapar `|` cuando forma parte del contenido;
- mantener una fila separadora válida;
- revisar que ninguna celda absorba una línea posterior.

## 6. Formatos machine-readable

### JSON

- construir un único valor JSON;
- ejecutar un parser;
- validar contra schema cuando exista;
- conservar tipos boolean, number, array y object;
- entregar comentarios fuera del payload.

### YAML

- ejecutar un parser YAML seguro;
- usar espacios de forma consistente;
- representar expresiones ambiguas como strings explícitos;
- validar claves requeridas y enums.

### Código

- ejecutar compilación o análisis sintáctico;
- ejecutar la prueba más pequeña que cubra el cambio;
- ampliar la validación según alcance y riesgo.

## 7. Contenido literal

Cuando `literal_required = true`:

- conservar orden, caracteres, espacios significativos y bloques;
- usar UTF-8 sin BOM;
- usar saltos LF;
- conservar newline final cuando el contrato lo requiera;
- calcular SHA-256 antes y después del transporte;
- comparar bytes y líneas;
- presentar diferencias exactas cuando exista una desviación.

Usar la fuente como autoridad y la copia de trabajo como representación temporal.

## 8. Escritura y readback

### Escrituras

- ejecutar lecturas independientes en paralelo cuando sea útil;
- ejecutar escrituras sobre una misma ruta en secuencia;
- confirmar el SHA o versión vigente antes de reemplazar;
- mantener archivos temporales dentro de una ubicación controlada;
- retirar temporales al cerrar la operación.

### Readback

Después de cada persistencia:

1. leer desde el destino;
2. recalcular SHA-256;
3. contar bytes y líneas;
4. ejecutar el parser o schema;
5. comparar con el contenido esperado;
6. registrar el identificador persistido: commit, blob, fila o versión.

Un write exitoso confirma transporte. El readback coincidente confirma integridad.

## 9. Validación determinista

Ejecutar:

```bash
python .claude/scripts/validate_artifact_output.py <archivo> --format auto --require-final-newline
```

Comparar contra valores esperados cuando estén disponibles:

```bash
python .claude/scripts/validate_artifact_output.py <archivo> \
  --expected-sha256 <sha256> \
  --expected-bytes <bytes> \
  --expected-lines <lineas>
```

El script devuelve JSON y códigos de salida:

```text
0 = PASS
1 = FAIL de validación
2 = BLOCKED por entrada o dependencia
```

Para contenido que se presentará en chat, usar el campo
`recommended_markdown_wrapper` de la evidencia.

Las validaciones específicas del dominio se ejecutan además de este validador.

## 10. Evidencia y estados

### Evidencia mínima

```json
{
  "artifact_path": "<path>",
  "format": "<format>",
  "sha256": "<64-hex>",
  "bytes": 0,
  "lines": 0,
  "parser_result": "PASS",
  "readback_sha256": "<64-hex>",
  "readback_match": true,
  "validator_result": "PASS",
  "evidence_refs": []
}
```

### Estados

Usar:

```text
READY_FOR_JUDGE
PASS_WITH_EVIDENCE
RETURN_TO_WORKER
PENDING_DECISION
BLOCKED
FAIL
```

Asignar el estado conforme al contrato del actor:

- worker: `READY_FOR_JUDGE`, `RETURN_TO_WORKER` o `BLOCKED`;
- juez: `PASS_WITH_EVIDENCE`, `RETURN_TO_WORKER`, `BLOCKED` o `FAIL`;
- orquestador: estado agregado sustentado por jueces y readback.

## 11. Delegación

Cada subagente recibe:

- objetivo concreto;
- inputs y versiones;
- rutas autorizadas;
- herramientas permitidas;
- output schema;
- assertions;
- validaciones;
- evidencia requerida;
- juez siguiente;
- límite de reintentos.

El agente principal verifica el resultado del subagente antes de integrarlo.

## 12. Plantillas positivas

### Inicio

```text
Lee las fuentes declaradas y resuelve target, versión, alcance, superficie y
criterios de cierre. Registra cualquier dato material pendiente.
```

### Construcción

```text
Construye únicamente los objetos autorizados. Conserva la información válida,
usa referencias resolubles y aplica el formato contractual.
```

### Validación

```text
Ejecuta el parser, schema, pruebas dirigidas y validador operativo. Repara cada
assertion dentro del alcance y conserva evidencia de cada intento.
```

### Persistencia

```text
Escribe en el destino autorizado, relee el resultado persistido y compara hash,
bytes, líneas, inventario y estructura.
```

### Cierre

```text
Declara el estado sustentado por evidencia. Incluye diferencias, identificadores
persistidos, assertions y siguiente paso.
```

## 13. Ejemplos

### Markdown con bloques anidados

Entrada: archivo Markdown que contiene bloques de tres backticks.

Aplicación:

```text
longest_backtick_run = 3
recommended_markdown_wrapper = "````"
```

Resultado: el archivo completo se presenta dentro de cuatro backticks y sus
bloques internos permanecen visibles.

### JSON transportado a GitHub

Aplicación:

```text
parse JSON
→ validate schema
→ compute SHA-256
→ write branch
→ fetch blob
→ compare SHA-256
→ report commit and blob
```

### Definición incompleta

Aplicación:

```json
{
  "result": "BLOCKED",
  "missing_inputs": ["source_version"],
  "completed_checks": ["target_resolved", "write_scope_resolved"],
  "next_action": "resolve source_version"
}
```

## 14. Fuentes de diseño

- Claude Code: `CLAUDE.md` compartido, imports `@path`, instrucciones concretas,
  workflows y validación basada en scripts.
- Claude Agent Skills: referencias a un nivel, progressive disclosure y ciclo
  `analizar → planificar → validar → ejecutar → verificar`.
- `microsoft/vscode`: instrucciones centrales que apuntan a guías especializadas,
  búsqueda ordenada, validación según riesgo y limpieza de temporales.
- `Significant-Gravitas/AutoGPT`: quick reference, entry points, ciclo explícito,
  estado persistente, gotchas y pruebas.
- `freeCodeCamp/freeCodeCamp`: schemas condicionales, tipos estrictos y mensajes
  de error verificables.

Las reglas de dominio y seguridad conservan precedencia.

## 15. Protocolo de pase para actualización de perfiles

### 15.1 Alcance y autoridad

Estado: `OPERATIVO_TRANSVERSAL`.

Aplicar a toda modificación de un perfil existente bajo `profiles/**` que se
resuelva como `ACTUALIZACION_PERFIL_LF`, directamente o por Router.

Supabase conserva autoridad canónica sobre operación, contrato, judge, binding,
ejecución y estado. Esta sección define el procedimiento reproducible de pase en
GitHub; no crea ni sustituye autoridad de gobernanza.

Precedentes demostrados: UI Architect y PR #254 (Quality Pack + Evidence Lineage
Reviewer LF).

### 15.2 Principios no negociables

1. **EKB primero.** Consultar recurrencias antes del primer write y enriquecer
   cualquier problema nuevo observado durante el pase.
2. **Binding antes del primer write.** Nunca escribir el candidato y crear la
   ejecución después para justificarlo.
3. **No receipts retroactivos.** Un receipt posterior no repara una secuencia
   temporal inválida.
4. **Exact-head real.** Validación, receipt, readback y merge deben referir al
   candidato que realmente se integrará.
5. **Fail closed.** `expected`, `pending`, `in_progress`, incertidumbre,
   divergencia Router/direct, missing receipt o falta de readback no son PASS.
6. **No force-push para carreras de base.** Integrar el `main` vigente conservando
   historia y cambios concurrentes.
7. **No PRs auxiliares para inspección.** Comparar ramas con compare commits/refs;
   abrir PR sólo para una integración real.
8. **No promoción implícita.** Una mejora de calidad no habilita runtime ni cambia
   por sí sola `CANDIDATO / READ_ONLY / NO_HABILITADO / BLOQUEADO`.
9. **No relajar gates para pasar.** Un conflicto de scope se corrige usando la
   ruta/operación gobernada; no ampliando allowlists sin autoridad específica.

### 15.3 Preflight obligatorio

Antes de cualquier GitHub write sobre el perfil:

1. resolver exactamente un perfil por Router/catálogo;
2. confirmar slug, `codigo_activo`, repo/path y estado actual;
3. resolver `ACTUALIZACION_PERFIL_LF`;
4. leer contrato y judge vigentes desde Supabase;
5. consultar EKB, incluyendo como mínimo:
   - `GOV-022`: incompatibilidad de scope/receipt/evidencia;
   - `GOV-024`: write anterior al binding canónico;
   - `RTE-010`: deriva de vocabulario/cobertura vista-enforcement;
   - `CI-014`: `main` avanza durante CI y vuelve stale el exact-head;
   - `OPS-005`: PR auxiliar usado indebidamente para comparar ramas;
6. crear la ejecución oficial del perfil antes del write;
7. demostrar `execution_bound_before_write = true` y
   `pre_write_gate_passed = true`, con scope y plan de regresión definidos;
8. leer el `main` actual y guardar su SHA;
9. crear rama `lf/**` desde ese SHA exacto.

No crear una ejecución manual o retroactiva para salvar un candidato que ya fue
escrito.

### 15.4 Construcción y evidencia

- Cambiar sólo paths autorizados.
- Preservar identidad, slug y estado de runtime salvo operación explícitamente
  autorizada para cambiarlos.
- No modificar workflows, allowlists o judges sólo para obtener PASS.
- Cuando el contract gate requiera `LF_OPERATION_CONTRACT_RECEIPT`, usar un
  receipt gobernado, ligado a la ejecución canónica y al candidato real.
- Prohibido inventar, reutilizar o emitir retroactivamente receipts.
- Después de cada write relevante, releer desde la rama remota, comparar blobs o
  hashes y registrar el exact-head en la ejecución.
- Ejecutar, según el perfil: validadores determinísticos, semantic judge,
  adversariales, holdout, Router/direct consistency, artifact/readback y
  upstream validity/freshness.
- Presencia, estructura, score o narrativa por sí solos nunca bastan para PASS.

### 15.5 CI exact-head y carrera de `main`

Ejecutar todos los required workflows sobre el HEAD actual del PR.

No continuar a merge mientras un required check esté `expected`, `pending`,
`in_progress`, `failure`, `cancelled` o ausente.

Inmediatamente antes del merge, releer `main`.

Si `main` no cambió desde la revisión integrada y todos los required checks están
`SUCCESS`, continuar al merge protegido.

Si `main` cambió mientras corría CI:

1. considerar stale la certificación anterior para efectos de merge;
2. **antes del siguiente GitHub write**, refrescar en Supabase el pre-write
   binding contra el nuevo `main`;
3. integrar el nuevo `main` en la rama sin force-push;
4. preservar todos los cambios concurrentes de `main` y superponer sólo los
   blobs autorizados del candidato;
5. actualizar exact-head y readback en Supabase;
6. volver a ejecutar todos los required workflows;
7. repetir hasta que `main` permanezca estable durante la certificación final.

No esperar a que finalice un CI que ya se sabe stale para strict-base sólo para
intentar reutilizarlo después.

### 15.6 Merge protegido

Antes de mergear comprobar simultáneamente:

- PR mergeable;
- `main` sigue en el SHA integrado;
- HEAD del PR no cambió;
- todos los required workflows están `SUCCESS` en ese HEAD.

Usar `expected_head_sha` cuando la herramienta lo permita.

### 15.7 Cierre post-merge

Después del merge:

1. leer el nuevo `main` y obtener el merge SHA;
2. releer blobs críticos desde ese `main`;
3. confirmar que no hubo promoción no autorizada de runtime/estado;
4. cerrar pasos canónicos en Supabase sólo con evidencia observada;
5. sincronizar catálogo/metadata del activo;
6. enriquecer EKB con recurrencias, causa, solución, validación y evidencia;
7. mantener la auditoría independiente separada: el builder no se autodeclara
   `REMEDIATED_VERIFIED`.

### 15.8 Condiciones de bloqueo

Bloquear y no mergear si ocurre cualquiera de estas condiciones:

- ejecución canónica ausente antes del write;
- `pre_write_gate_passed` no demostrado;
- receipt faltante, inválido, replayed o fuera de scope;
- artifact/readback no verificado;
- upstream stale/invalid;
- divergencia Router/direct;
- incertidumbre semántica;
- required check distinto de `SUCCESS`;
- `main` avanzó y aún no se refrescó binding/base/CI;
- identidad o runtime cambiaron sin autorización;
- se requiere relajar un gate para obtener PASS.

### 15.9 Handoff mínimo entre chats o agentes

Todo pase debe incluir:

- repo, PR y branch;
- profile slug y `codigo_activo`;
- operation code y execution id;
- base `main` SHA;
- candidate exact-head;
- paths autorizados;
- receipts aplicables;
- validaciones funcionales y digests;
- required workflow runs y conclusiones;
- estado actual de `main`;
- EKB codes relevantes;
- runtime/status final;
- próximo gate explícito.

La omisión de estos campos no autoriza a continuar por inferencia.

### 15.10 Errores operativos prohibidos

- Crear un PR auxiliar sólo para comprobar diferencias entre ramas.
- Crear una rama desde un `main` stale sin releerlo.
- Reutilizar un SUCCESS perteneciente a otro HEAD.
- Cerrar una ejecución antes del readback post-merge.
- Fabricar evidencia no observada por el sistema.
- Publicar un protocolo o evidencia en una ruta que el gate global mantiene
  default-denied; usar las rutas exactas autorizadas o escalar la gobernanza.

### 15.11 Evidencia inicial del patrón

PR #254 cerró Quality Pack + Evidence Lineage siguiendo este patrón:

- base refrescada cuando `main` avanzó;
- binding refrescado antes del siguiente write;
- integración sin force-push;
- CI repetido sobre el nuevo exact-head;
- `Validate LF Packs`, `lf-contract-check` y
  `LF Bootstrap Reproducibility Probe` en `SUCCESS`;
- comprobación final de estabilidad de `main`;
- merge protegido;
- readback post-merge;
- cierre Supabase y enriquecimiento EKB.

Reutilizar esta sección para los perfiles restantes con la misma clase de bloqueo.
