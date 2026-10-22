# RW1-06_C1 — Cifrado de custodia privada V2 (GnuPG)

**Estado:** implementación candidata y prueba sintética de transporte; NO constituye atestación de proveedor, independencia del revisor, corpus real, C1 DONE ni aprobación de admisión V2.

## Propósito y titularidad

Cubrir una brecha concreta: el productor y el conector de Google Drive compartían la misma identidad y podían leer archivos JSON, aunque la carpeta dijera `shared=false`. Una carpeta privada de Drive NO protege un corpus en texto claro frente a una identidad compartida.

Se reutilizan los carriers existentes: commit y readback Git, carpetas privadas Drive como **transporte cifrado**, acción/spec de RW1-06 en el Engineering Plan, y Migration Train para cualquier binding en BD. Se añade **únicamente** una utilidad local de cifrado, no un servicio/Router/API/ejecutor nuevo.

Herramienta: `sandbox/lf_contract_gate_test/router_wave/seal_rw106_c1_gpg_v2.py` (GnuPG, cifrado a clave pública).

## Paso 0 — la separación antes del corpus (GAP mientras falte)

1. Custodio independiente: crear una clave GnuPG real desde un principal fuera de los contextos con acceso del productor, **sin exportar el secreto ni la passphrase** a este proyecto, repositorio, CI, Drive conectado ni chat productor.
2. Publicar únicamente su clave pública y huella íntegra de 40 hex, más evidencia no sensible de que esa huella fue obtenida/autorizada por el custodio y de que la clave privada no está disponible al productor. No confiar en una huella suministrada solo por el productor.
3. El coordinador emite un `attempt_ref` anclado al Git blob/commit real (Git URI de `RW1_06_C1_CAPTURE_ATTEMPT_V2_001.json`) y confirma preflight, fuentes, canal revisor y capacidad de recuperación cifrada. El Git URI **no es** una atestación de chat ni prueba aislamiento.
4. Solo después de lo anterior, en **contexto revisor materialmente separado**, autorizar una única nueva generación de corpus (mínimos 12/24/2, F01–F13), y pre-registrar oráculos antes de observar cualquier RAW. Los dos corpus históricos son no admitidos y no se reutilizan.
5. Antes de una generación real, la aprobación V2 debe definir expresamente la evidencia aceptable de separación para sustituir el requisito de URL del chat del validador V1. No hacerlo por excepción implícita.

## Paso 1 — cifrado únicamente del lado revisor

En una máquina/entorno del revisor que ya contenga `corpus.private.json` y `manifest.private.json` y cuya clave privada no esté allí, ejecutar:

```sh
python3 sandbox/lf_contract_gate_test/router_wave/seal_rw106_c1_gpg_v2.py \
  --corpus corpus.private.json \
  --manifest manifest.private.json \
  --public-key custodian-public.asc \
  --recipient-fingerprint <HUELLA_PUBLICA_DE_40_HEX> \
  --attempt-ref 'github://cristhianlujan/claude-persona-lf-patch@<SHA40>/docs/programming-agent/router_wave/RW1_06_C1_CAPTURE_ATTEMPT_V2_001.json' \
  --output-dir ./ciphertext_output
```

`ciphertext_output` debe existir y estar vacío respecto de los nombres `corpus.gpg`, `manifest.gpg` y `commitment_candidate.json`. El programa importa **solo** la clave pública dentro de una instalación GPG temporal y comprueba que **no contiene ninguna clave secreta**. Valida IDs, tipos, mínimos, F01–F13, oráculos y fuentes; cifra separadamente los dos archivos y calcula SHA-256 de bytes reales del texto claro, ciphertext y clave pública.

Nunca imprimir secretos ni subir texto claro, semilla, nonce, oráculos o passphrase al productor.

## Paso 2 — transporte privado y comprobación de recuperación

- Drive conectado puede transportar exclusivamente `corpus.gpg` y `manifest.gpg` (o cualquier almacén ya autorizado con control de acceso); el acceso del productor al ciphertext no permite por sí mismo descifrarlo.
- Custodio verifica digest de ciphertext recuperado, descifra en su entorno independiente, compara SHA-256 de los bytes obtenidos con `holdout_content_sha256` y `holdout_manifest_sha256`, y emite **solo prueba opaca de custodia/recuperación**, sin divulgar ningún dato reservado al productor.
- La huella GPG y los SHA no demuestran por sí solos que quien cifra o descifra sea independiente. Requieren identidad responsable y evidencia separada.
- No se ha realizado todavía una carga real de ciphertext nuevo desde esta herramienta al Google Drive conectado. La copia de JSON existente es solo una prueba de persistencia. No marcar `CUSTODY_VERIFIED` hasta completar el verdadero ciclo con principal aislado o clave inaccesible al productor.

## Paso 3 — public precommit y orden canónico

`commitment_candidate.json` solo tiene hashes y metadatos. Se registra mediante Git **antes** de la salida RAW del productor. Readback de commit y blob; anclar `attempt_ref` y versión normativa exacta. C2 debe referenciar el commit público original y comparar precedencia por evidencia externa, no por timestamp declarado.

El candidato emitido conserva:
`external_precommit_persisted=false`, `custodian_independent_readback_verified=false`, `separate_reviewer_evidence_verified=false`, `provider_attested=false`, `independent_review=false` y `checkpoint_done=false`.

No actualizar esas banderas hasta contar con pruebas materiales y con la autoridad de admisión explícitamente aceptada. El auto-test crea una clave **efímera y sintética de CI**, cifra dos fixtures, descifra en otro keyring y verifica las huellas; no es evidencia de independencia real.

## Controles y bloqueos

| Caso | Resultado |
|---|---|
| Faltan clave pública y fingerprint corroborado del custodio | GAP antes de generar casos |
| El productor tiene la clave privada o puede leer texto claro | BLOCK |
| Huella de clave importada distinta de la huella autorizada | BLOCK |
| Corpus insuficiente, fuentes equivocadas, oráculos ausentes, RAW anticipado | BLOCK |
| Integridad de ciphertext o plaintext no coincide tras recuperar | BLOCK |
| Sin compromiso Git previo a RAW o evidencia de separación | GAP/BLOCK según contrato |
| Solo self-test, misma identidad conectada o simple `shared=false` | NO PASS |
| Acciones/efectos por aprobación semántica del especialista | BLOCK, permanece ACT-0001 |

Este diseño no habilita ejecución del perfil, migración, runtime, producción ni cierre C1/C2/C3. RW1-06_C3 conserva nivel FULL.

## Custodian verification CLI

Only from the separately controlled custodian host, with the custodian's local GPG home configured and access to the three encrypted-delivery files:

```sh
python3 sandbox/lf_contract_gate_test/router_wave/seal_rw106_c1_gpg_v2.py --custodian-home PATH_TO_CUSTODIAN_GNUPG_HOME --output-dir PATH_TO_ENCRYPTED_DELIVERY
```

The verifier checks both ciphertext digests against the public candidate, decrypts locally and checks both original plaintext SHA-256 values without printing the secrets. A tampered ciphertext is rejected. Its JSON readback is cryptographic integrity evidence only; it does not attest that the real custodian or reviewer was independent.
