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
