# PR #93 · LOTE-E.15 · Controles normativos

Este lote corrige CA-N125–CA-N128 y endurece CA-N133–CA-N143, además de
incorporar un checklist preventivo reutilizable. No autoriza merge, despliegue ni ejecución runtime.

## CA-N125 · marcador literal

`PR93_LOTE_E14_NEGATIVE_TESTS.py` ya no publica ningún contador que no respalde
con ejecución observable.

- El contador literal `12/12` de la matriz histórica E.13 queda **eliminado**.
  E.14 no ejecuta esa matriz: sus seis runners son stubs fail-closed. El
  marcador prohibido no se reproduce aquí para no reintroducir la firma en el
  corpus vinculante (ver CA-N139).
- En su lugar se publica la declaración no numérica
  `E13_NEGATIVE_MATRIX=NOT_EXECUTED_BY_E14`.
- `PASS_E14_NEGATIVE_MATRIX=<rechazados>/<ejecutados>` se deriva de dos
  contadores incrementados por cada caso realmente ejecutado. El runner aborta
  si ambos contadores difieren.

## CA-N126 · pruebas contra el artefacto desplegable

Todos los casos negativos ejecutan `PR93_LOTE_E14_VERIFY.py` como subproceso
mediante `sys.executable`, y verifican código de salida **y** mensaje esperado.

Para cada caso de marcadores, `rebuild_bundle()` reconstruye un bundle
íntegramente coherente: transcripts, sobre completo, digests, tamaños, conteos
de línea, objeto semántico y **ancla externa recalculada**. Un rechazo prueba
entonces que actuó una guarda de contrato, no un desajuste de hash residual.

Las comprobaciones in-process contra `PR93_LOTE_E14_SEMANTICS` se conservan
únicamente como complemento y nunca como sustituto del subproceso.

## CA-N127 · ausencia de bundle parcial

El bundle nunca se ensambla en su ruta final:

```text
directorio de staging exclusivo (mkdtemp, mismo sistema de archivos)
        ↓
escritura de los 9 archivos con creación exclusiva ("xb")
        ↓
fsync de cada archivo y del directorio de staging
        ↓
rename atómico único al destino definitivo
        ↓
fsync del directorio padre
```

Cualquier excepción descarta el staging por completo y devuelve código 20, sin
dejar nada en la ruta de destino. La limpieza solo alcanza directorios que el
propio proceso creó de forma exclusiva y registró en `OWNED_STAGING`.

`renameat2(RENAME_NOREPLACE)` es obligatorio y falla si el destino existe como
archivo, directorio o symlink. No existe fallback a `rename(2)`; un host o
filesystem sin soporte falla cerrado.

## CA-N128 · inventario físico exacto

`verify_bundle_inventory()` compara el listado real del directorio
(`os.scandir`) contra los nueve nombres permitidos y exige que cada entrada sea
un archivo regular que no sea symlink. Se rechaza:

- archivo regular adicional;
- subdirectorio adicional;
- symlink adicional o symlink que suplante un archivo permitido;
- archivo oculto adicional.

La comprobación **no** se apoya en `evidence_files` declarado en el recibo y se
ejecuta antes de leer el recibo. El recibo debe llamarse exactamente
`PR93_E14_RECEIPT.json`.

## CA-N143 · limpieza ligada a descriptor

`discard_owned_tree()` tiene una única implementación activa. La ruta objetivo
se abre con `O_DIRECTORY | O_NOFOLLOW`, se compara mediante `fstat()` contra
`(st_dev, st_ino)` registrado y su contenido se elimina exclusivamente con
operaciones relativas al descriptor.

Antes de retirar el nombre superior se vuelve a verificar la identidad. El
directorio se desacopla mediante `renameat2(RENAME_NOREPLACE)` hacia un nombre
privado y se comprueba nuevamente el inode antes de `rmdir`. Si el nombre fue
sustituido por un directorio o symlink extranjero, la limpieza devuelve `False`,
no emite ancla externa y preserva `FOREIGN_SENTINEL`.

La matriz ejecuta dos sustituciones deterministas:

- `cleanup-name-swap`;
- `cleanup-symlink-swap`.

Ambas deben pasar de forma independiente y dentro de la regresión completa.

## Versión de contrato

`governance_contract_version` pasa de `PR93_E14_V1` a `PR93_E15_V1`. Es un
cambio incompatible deliberado: los bundles emitidos bajo el contrato anterior
no satisfacen el inventario estricto y deben recapturarse.

## Checklist preventivo transversal

Aplicable a E.15 y lotes posteriores.

1. No afirmar “cero force-push” sin evidencia histórica verificable. El estado
   fast-forward actual no es historial.
2. Separar siempre tres registros distintos: estado fast-forward actual,
   historial remoto, e inferencia.
3. Tratar toda URI con contraseña en `argv` como riesgo operacional: es visible
   en la tabla de procesos del host. Preferir `PGPASSFILE` o credenciales de
   entorno cuando el destino lo permita.
4. Separar siempre `STATIC_PASS`, `SYNTHETIC_PASS` y `RUNTIME_PASS`. Ninguno
   implica al siguiente.
5. No cerrar un CA sin enunciado canónico, criterio de aceptación y evidencia
   correspondiente. Los tres, no dos.
6. La configuración YAML de workflows describe disparadores; no sustituye el
   inventario real de ejecuciones de GitHub Actions.
7. Las autoafirmaciones del capturador se etiquetan como declarativas
   (`declaration_kind: SELF_ASSERTED_NOT_MEASURED`) o se sustituyen por
   mediciones. Nunca se leen como evidencia observada.
8. El módulo semántico compartido entre capturador y verificador otorga
   **independencia de integridad** (detecta recibo falsificado), no
   independencia algorítmica (no detecta un error común de algoritmo).
9. `__pycache__/`, `*.pyc` y `*.pyo` quedan ignorados en esta ruta como defensa
   adicional, sin eliminar `sys.dont_write_bytecode` de ningún módulo.
10. Ninguna evidencia estática o sintética autoriza merge, runtime ni
    despliegue.

## Fuera de alcance

Permanecen abiertos y no se cierran por inferencia: CA-N93 (requiere inventario
canónico autenticado de GitHub Actions), CA-N96, CA-N102 (requiere enunciado
canónico), CA-N103, CA-N110, CA-N111 y la ejecución runtime contra el baseline
LF real.
