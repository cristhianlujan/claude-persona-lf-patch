# RW1-06_C1 — Decisión D1: evidencia de separación del revisor sin GnuPG (V1)

**Estado:** PROPUESTA PARA DECISIÓN DEL PROPIETARIO. No está aprobada ni activa. No cambia contratos, validadores existentes, base de datos, C2 ni C3.
**Ancla:** repo `cristhianlujan/claude-persona-lf-patch`, PR #3070 (Draft), snapshot `ec5d8ce5637c2d118941cfe4b3c88ae4fd325024`, source policy blob `138efc3285ee5226c107827c66f84ced6be4afcb`, intento `RW106-C1-V2-001` (`github://cristhianlujan/claude-persona-lf-patch@76924bbb8a1ede147412cdd1be8f98619b659776/docs/programming-agent/router_wave/RW1_06_C1_CAPTURE_ATTEMPT_V2_001.json`).

## Diagnóstico

C1 sigue `PENDING` por dos brechas: separación del revisor y custodia del corpus. El camino GPG (custodio externo, clave pública, ciphertext) las resuelve criptográficamente, pero exige un custodio y un GnuPG que hoy no existen. Además, `validate_rw106_c1_precommit_order_v2.py` solo acepta el esquema cifrado (`corpus_ciphertext_sha256`, `recipient_fingerprint`), de modo que ninguna otra ruta puede admitirse sin un cambio gobernado.

La política congelada ya describe otra mecánica: el revisor conserva seed y nonce hasta el compromiso RAW del productor, con manifest y content digest fijados antes (`holdout_protocol`). Eso es *commit-reveal*, y no necesita claves.

## Roles (no se asume que dos modelos distintos garantizan independencia)

| Rol | Quién | Puede ver | No puede ver |
|---|---|---|---|
| Productor | Claude | fuentes públicas fijadas, hashes del commitment, bundle solo tras su RAW | corpus, oráculos, nonce, conversación del revisor, antes del RAW |
| Revisor | GPT Native, chat nuevo fuera del proyecto LF, memoria desactivada | fuentes públicas fijadas | mensajes, claves o salidas del productor |
| Custodio | el propio bundle sellado del revisor + propietario como responsable humano | su archivo | — |
| Notario de orden | Git (commit del compromiso antes del RAW) | hashes públicos | cuerpos |

## Protocolo (4 intervenciones del propietario, sin claves ni gestión de archivos)

1. **Aprobar D1** (abajo) y firmar la declaración de separación (plantilla abajo).
2. **Handshake.** El productor emite un nonce y un prompt; el propietario lo pega en un chat nuevo de ChatGPT (app móvil o perfil de navegador sin extensión de Claude, fuera de cualquier Proyecto, memoria desactivada) y devuelve la respuesta. El productor comprueba el SHA-256 y que declara no estar en un Proyecto.
3. **Generación y compromiso.** El propietario pega el prompt de generación (emitido con `prompt generate`). El revisor autora 13/26/2 casos y oráculos y ejecuta el verificador extraído del sellador existente. Devuelve solo un bloque de hashes y un enlace a un archivo. El propietario descarga ese archivo **fuera de carpetas conectadas a Claude**, y pega aquí solo el bloque de hashes y la URL privada del chat (se hashea y no se abre). El productor publica el commitment en Git.
4. **Revelación (tras el RAW del productor en C2).** El propietario adjunta el archivo. `verify-reveal` comprueba hashes, mínimos 12/24/2, F01–F13, oráculos preregistrados y orden Git.

## Qué cambia respecto del mecanismo vigente (requiere aprobación)

- **D1-a.** Evidencia aceptada para `separate_reviewer_evidence=true` de `RW1-06_C1`: pasa de «custodio GPG externo con clave pública y prueba de ciphertext» a «commit-reveal con bundle sellado del revisor + declaración privada del propietario + orden Git + integridad en la revelación».
- **D1-b.** `reviewer_reference` pasa de URL de chat pública a `reviewer_locator_sha256` (hash de la URL privada).
- **D1-c.** Se acepta el nuevo esquema `RW106_C1_COMMIT_REVEAL_COMMITMENT_V1` junto al cifrado, sin eliminar este último.

No cambia: ACT-0001 como autoridad del Router; Migration Merge Train para cualquier migración; C3 FULL; 12/24/2 mínimos; congelado de fuente; `provider_attested=false`; `independent_review=false` (no existe atestación del proveedor); C2/C3 siguen `PENDING`.

| Opción | Efecto |
|---|---|
| **A. Mantener GPG** | Sin cambio normativo. Bloqueado hasta que exista un custodio externo con GnuPG. |
| **B. Commit-reveal + declaración del propietario (recomendada)** | Desbloquea C1 con 4 intervenciones. Independencia = atestada por el propietario, no criptográfica. |
| **C. Esperar atestación del proveedor** | Máxima garantía; sin fecha ni mecanismo disponible. |

## Riesgos residuales (no los elimina esta propuesta)

- El productor dispone de herramientas de navegador; no existe barrera técnica absoluta hacia ChatGPT. Mitigación: canal fuera del navegador del productor (app móvil o perfil sin extensión), compromiso del productor de no abrir dominios de OpenAI en este checkpoint y transcripción como evidencia.
- Una fuga por el propietario no se detecta; es control de proceso.
- «No estoy en un Proyecto» es autodeclaración del revisor; sin atestación del proveedor.
- Si el archivo se pierde antes del RAW, se rehace con otro intento: no se quema nada. Después del RAW, un fallo de integridad es `HOLDOUT_INTEGRITY_GAP`.
- Los mínimos y la estructura no prueban la calidad del corpus; eso lo sigue juzgando C3 FULL.

## Declaración del propietario (plantilla; el hash del texto exacto va al commitment)

«Declaro que abrí el chat revisor en [dispositivo/perfil], fuera de cualquier Proyecto, con memoria desactivada; que no le compartí mensajes, claves, corpus previos ni claves de respuesta del productor; que guardé el archivo sellado fuera de carpetas conectadas a Claude; y que no lo compartiré con el productor antes de la revelación. Fecha/hora y nombre: [..].»

## Evidencia de verificación (ejecutada en esta sesión, solo sintética)

- Fuentes congeladas: 6/6 blobs idénticos en snapshot y en `main` actual (`dad815a46d484130c30f6535eb9f5a46461138e4`); 7/7 MD5 de funciones del Router en vivo coinciden con `runtime_definition_md5`. Sin deriva.
- Estado vivo: `RW1-06_C1/C2/C3 = PENDING`, sin evidencia; la migración candidata `20261022013100` no está aplicada.
- Validadores existentes (head `3cde5dfbc92cf675e6a69d00db07b361aef5a9fa`): 5/5 self-tests `PASS_SYNTHETIC_ONLY`, sin modificarlos.
- `verify_rw106_c1_commit_reveal_v1.py self-test`: `PASS_SYNTHETIC_ONLY`, 37 negativos rechazados, ida y vuelta del snippet del revisor con el verificador y blobs fijados releídos de Git. Prueba de mutación: 5/5 sabotajes del verificador son detectados por el self-test.
- No se generó corpus real, no se consultó al revisor, no se abrió ningún chat ni se ejecutó C2.

## Registro de decisión del propietario

[ ] A  [x] B  [ ] C  [ ] B con cambios: ______    Fecha: 2026-10-22 04:19 (Lima), indicada por el propietario en el chat de la sesión

Hasta que esté marcada, `RW1-06_C1` permanece `PENDING` y no se emite ningún prompt al revisor.
