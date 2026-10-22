# RW1-06_C1 — Alta del custodio independiente (paquete operativo V1)

**Estado:** SOLICITUD PREPARADA / pendiente de credenciales y evidencia emitidas por un custodio externo. No es admisión C1 ni certificación de independencia.

## Identidad del intento y autoridad

- Unidad: `RW1-06_C1`; repositorio: `cristhianlujan/claude-persona-lf-patch`.
- Intento operativo: `RW106-C1-V2-001`.
- **Referencia Git inmutable validada por readback:** `github://cristhianlujan/claude-persona-lf-patch@76924bbb8a1ede147412cdd1be8f98619b659776/docs/programming-agent/router_wave/RW1_06_C1_CAPTURE_ATTEMPT_V2_001.json`.
- Blob exacto de ese intento: `9e0d069de56e61ad3c60a3f117a5956daa4fce35`.
- Snapshot normativo: `ec5d8ce5637c2d118941cfe4b3c88ae4fd325024`.
- Source policy blob: `138efc3285ee5226c107827c66f84ced6be4afcb`.
- Separación y revisión: pendientes. C1/C2/C3 permanecen `PENDING`; el repositorio tiene PR #3070 en Draft. La migración candidata NO está aplicada.
- Este documento no crea una persona, una cuenta, una clave ni una atestación.

## Quién puede ser custodio

Una persona o entidad con **entorno y credenciales realmente fuera del alcance del contexto productor**. Puede ser el propietario operando un dispositivo y llavero aislados, siempre que exista evidencia de que el productor/los conectores de este proyecto no pueden acceder a esa clave. **La misma cuenta Drive conectada no constituye aislamiento.** La clave privada nunca se genera, importa, comparte ni verifica en un chat productor, CI, GitHub, Drive del productor o un conector con privilegios compartidos.

La identidad del custodio y su separación material deben acreditarse mediante referencia documental privada y controlable por el owner; esa declaración no equivale a atestación del proveedor.

## Alta criptográfica realizada por el custodio, fuera de este entorno

El custodio, en su propio dispositivo con GnuPG disponible, genera una clave dedicada si aún no dispone de una adecuada. En GnuPG 2.2+/2.4+, una opción es usar el asistente interactivo `gpg --full-generate-key` para crear la clave y un subkey con capacidad de cifrado; elegir expiración, passphrase y proteger físicamente el llavero. No usar una contraseña fijada en un comando, historial de shell o plantilla pública. La clave privada se conserva únicamente en el dispositivo del custodio.

Con el fingerprint obtenido del asistente, exportar **solo** su clave pública (a una carpeta que no sea del repositorio):

```sh
gpg --fingerprint --with-colons
gpg --armor --export FINGERPRINT_40_HEX > rw106-c1-custodian-public.asc
gpg --show-keys --with-colons rw106-c1-custodian-public.asc
sha256sum rw106-c1-custodian-public.asc
```

**Entregar únicamente:**
1. El archivo `rw106-c1-custodian-public.asc` con bloque `-----BEGIN PGP PUBLIC KEY BLOCK-----`, su fingerprint completo y SHA-256 del archivo.
2. Una **referencia privada verificable** de la declaración de custodia: principal que controla el dispositivo, ausencia de permisos del productor, separación frente a contexto/cuenta compartidos y posibilidad de recuperación después de reiniciar sesión.
3. Aceptación de realizar una prueba inocua de entrega cifrada, descifrado y SHA-256 por el custodio; el productor solo recibirá veredicto/digests, jamás el texto descifrado.
4. Identificación de un medio estable de entrega de los ciphertexts `.gpg` (el Drive conectado puede servir de transporte de ciphertext, no como almacén de clave privada ni corpus plano).

**No entregar:** claves privadas, keyring completo, archivos `private-keys-v1.d`, passphrase, nonce del holdout, casos, oráculos, frases de recuperación ni credenciales personales.

## Contrato de admisión del alta

`CUSTODIAN_KEY_READY` requiere comprobación independiente, no un booleano emitido por el modelo:

- Coincidencia de fingerprint importado con el fingerprint recibido por canal independiente y autorizado.
- Clave pública vigente y con capacidad de cifrado; revocada, expirada, sin subkey de cifrado o fingerprint inválido => `BLOCK`.
- Evidencia del custodio y evidencia de que el productor carece de clave privada. Permiso `shared=false` de Drive no cuenta.
- Prueba con *fixture sintética*, usando el programa existente `sandbox/lf_contract_gate_test/router_wave/seal_rw106_c1_gpg_v2.py` y `--custodian-home` en equipo separado; hashes reales, readback externo y cero secretos en el PR.
- Sólo después, decisión explícita de gobernanza sobre la equivalencia de separación V2; sin esta autorización => `GAP`. `provider_attested=false` salvo prueba auténtica del proveedor.

El Git intento inmutable y la clave pública no prueban, por sí mismos, independencia del revisor. No se generará un corpus nuevo hasta completar la preparación y pasar todos los gates anteriores.

## Flujo tras recibir la clave pública

1. Verificar material público, fingerprint y capacidad de cifrado; registrar SHA-256 real y un recibo de enrollment público sin información sensible.
2. Registrar aparte la evidencia privada de no acceso del productor y de identidad del custodio.
3. Ejecutar prueba real con ciphertext sintético; verificar por custodio aparte y conservar hash del recibo.
4. Mantener `RW1-06_C1=PENDING` mientras quede cualquier GAP.
5. Tras autorización formal V2 y preflight, crear una única revisión nueva fuera del contexto LF con corpus 12+/24+/2+ y oráculos pre-registrados; cifrar con la pública autorizada, transportar ciphertext, recibir comprobación del custodio; publicar compromiso en Git antes del RAW C2.
6. C2 y C3 FULL conservan sus propios gates. No ejecutar migración/Train/producción desde este documento.

## Bloqueo actual

`CUSTODIAN_PUBLIC_KEY_AND_SEPARATION_PROOF_NOT_RECEIVED`. La siguiente acción requiere la participación de un custodio realmente aislado; repetir prompts dentro de la misma conversación NO resuelve ese bloqueo.
