# D13 — Propuesta de contrato operativo PIP-1 / ChatGPT (Paulo)

Fecha: 2026-11-01. Estado: RFC / NO AUTORIZADO / SOLO LECTURA.

## Evidencia y limite
- Carril D implementa RunContract, Inventory, Receipt, Outcome y transition, pero el camino operational=True bloquea acreditacion.
- PR #3402 demostro ChatGPT a GitHub y pruebas de observacion; 55 pruebas PASS sobre HEAD f3bbcea76d8ab0a864287173b7d62026fade6fc6.
- Simple Executor no admite el plan PG sin bindings; tampoco hay proveedores de cierre vinculados a ese plan.
- ORQUESTACION_PIPELINE_LF (ACT-0058) ejecuta CAPTURA, HOMOLOGACION, ANALISIS, KB_WRITE: no es runtime PIP-1.
- CIERRE_CHECKPOINT_INGENIERIA_LF sigue OP_CANDIDATE / CANDIDATO_READ_ONLY.
- No se identifico writer/readback operativo PIP-1 en las fuentes inspeccionadas; esto no demuestra inexistencia global.

## Interfaz propuesta — no es un contrato productivo
Entrada exclusiva desde runtime confiable: plan, execution_id, run_id, CP, unidad, HEAD SHA1, SHA256 de catalogo, contrato e inventario, scope y actor autorizado.
Readback: registro canonico del run, operacion activa, proveedor independiente, recibo persistido y lectura posterior a la transicion. Verificar identidad cruzada y frescura.
Salida hacia ChatGPT: estado observado, sugerencia y bloqueo; jamas un permiso fabricado por el chat.
Autoridad para cambios: solo runner y operacion autorizados de LF; no un JSON, hash, PR o booleano.

## Pruebas negativas obligatorias
- Run o execution_id ajenos: BLOCK.
- Plan, unidad o checkpoint ajenos: BLOCK.
- Drift de HEAD, inventario, contrato o catalogo: BLOCK.
- Recibo de fixture, proveedor ajeno o replay: BLOCK.
- Operacion en CANDIDATE o READ_ONLY: BLOCK.
- Estado DONE sin recibo validado: BLOCK.
- Doble escritura y concurrencia: BLOCK.
- Readback posterior inconsistente: BLOCK.
- PASS autentico: solo evaluable por autoridad externa, no cierre automatico del chat.

## Decisiones del owner de Carril D / gobernanza
A. Codigo de operacion/capacidad aprobado para PIP-1.
B. Registro canonico, version de writer y permisos de RunContract + SHA.
C. Proveedor independiente y forma de readback de recibos por checkpoint.
D. Procedimiento de transicion, PASE y revision independiente.
E. Alcance del primer ensayo real y autorizacion explicita si requiere escrituras.

## Proximo trabajo sin retrabajo
1. Confirmar estas cinco decisiones con contratos existentes antes de crear otro runtime.
2. Reutilizar matriz adversarial del PR #3402 y probar eventual adaptador sin escrituras hosted.
3. Mantener PR Draft y no declarar DONE por pruebas locales.
4. Solo despues ejecutar un caso PG admitido y registrar sus evidencias.

No se habilitan SQL de escritura, Router, merge ni cierres de checkpoints con este RFC.