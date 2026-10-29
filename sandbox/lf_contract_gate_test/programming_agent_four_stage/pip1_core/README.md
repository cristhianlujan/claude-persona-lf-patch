# PIP-1 · Núcleo puro D-01/D-03 (EXPERIMENTAL)

No contiene operaciones GitHub, Supabase, Router, recorder, ledger, Worker, Runner ni efectos de infraestructura. No activa el pipeline ni concede autoridad al inventario.

## Ejecutar

```sh
python -m unittest discover -s tests -v
python -m pip1_core.cli /ruta/al/PROGRAMMING_PIPELINE_INVENTORY_CANDIDATE_V1.json
```

El CLI valida identidad/digest/estructura y muestra orden topológico. La ruta de entrada debe apuntar a bytes del **archivo real** del HEAD exacto del PR #3220 para validación contra la fuente; los tests locales usan una **fixture sintética explícita** con conteos y 22 edges, no prueba operacional ni validación byte a byte del archivo remoto.

## Contratos e integración futura

- `RunContract` (pipeline, versión, ejecución, scope, executor, pins y estado candidato), `Receipt` (identidad exacta, proveedor, hash, origen), `Outcome` (estado y motivo), `Inventory` (CP y REQUIRES).
- `load_inventory()` toma las unidades/checkpoints del inventario; nunca enumera los 108 como fuente hardcoded. Comprueba SHA-256 canónico del `inventory_core`, cobertura y topología.
- `transition()` es pura y rechaza transiciones ilegales, receipts ajenos y elegibilidad sin precedencias.
- `verify_closure()` exige los 97 checkpoints operacionales con receipts compatibles y devuelve como máximo `SYNTHETIC_ONLY` (nunca un cierre acreditado); PG-00 se mantiene **prerrequisito externo** y no se certifica aquí.
- `operational=True` **siempre bloquea** (`EXTERNAL_CLOSURE_AUTHORITY_NOT_INTEGRATED` / `EXTERNAL_RECEIPT_AUTHORITY_NOT_INTEGRATED`) hasta que exista un verificador de autoridad independiente. **No usar para cierre operacional**.
- No se habilita todavía cierre con N/A, porque falta modelar una autoridad verificable sin inventarla.

## Gobernanza

El código está en un repositorio Git temporal local aislado, rama `lf/pip1-d01-d03-isolated`; no se hizo push, PR, etiquetas ni merge. PASE real exige materializar la rama en el repo autorizado, clasificar paths y correr controles contra `main` vigente; no se ejecutó sobre este repositorio local sin el árbol del repo principal.

## D-04 hardening (28 Oct 2026)

**Alcance:** núcleo puro; prohibido conectarlo a sistemas operacionales. Por seguridad el parámetro `operational=True` siempre bloquea la acreditación y el cierre hasta que se integre un verificador de autoridad independiente, fuera de este lote. Las pruebas sintéticas jamás implican un cierre real.

**Inventario real:** se consultó GitHub por el commit SHA exacto; la red de este contenedor no permitió materializar su contenido. `verify_exact_inventory.py` es la verificación reproducible pendiente de ejecutar en un checkout autenticado/con red. Puede recibir `--file` con bytes exactos o descargarlos por URL pinned. Verifica además el Git blob SHA1 y computa ambos SHA256. No sustituir con fixtures.

```bash
python -m unittest discover -s tests -v
python -m compileall -q pip1_core tests verify_exact_inventory.py
python verify_exact_inventory.py --file /ruta/descarga-exacta.json --out inventario_verificado.json
python -m pip1_core.cli inventario_verificado.json --expected-digest cd2f7a964b9901d9e58b8d5f4271532f480966424d37fd2d9a40332a7b440ffb
```

Documentos nuevos: `docs/D04_ADVERSARIAL_REVIEW.md`, `D04_INTEGRATION_MATRIX.md`, `D04_GOVERNANCE.md`, `D04_NEXT_BACKLOG.md`, `D04_VALIDATION_REPORT.md`. Revisión propia, no independiente. PASE NOT_RUN. **No hay migraciones, API/DB adapters, scheduler, locks ni credenciales.**

## D-05

Ver `docs/d05/VALIDATION_REAL_SOURCE.md`, `docs/d05/INDEPENDENT_REVIEW_AND_PR.md` y `docs/d05/CHANGES_AND_GOVERNANCE.md`. No se afirma ejecución Python contra el inventario auténtico, PASE PASS ni revisión independiente.

## Estado C3 (29 Oct 2026)

- Pruebas: **50 únicas** (`python -m unittest discover -s tests`), estables con 20 valores de `PYTHONHASHSEED`.
- `mypy==1.11.2` sobre `pip1_core` y `verify_exact_inventory.py`: sin errores. `ruff==0.6.9 check` (configuración por defecto) sobre núcleo, CLI, verificador y pruebas: sin errores. `ruff format` no es exigido para esta ruta y no se aplicó.
- Revisión independiente del código posterior a C1/C2/C3: pendiente. PASE: ver la descripción del PR. `operational=True` sigue cerrado.
