# Procesador ZIP transversal v0.5 — contenido verificado, candidato

Alcance skill-only. El ZIP es formato de transporte, no fuente ni conector. Reutiliza un solo lector del directorio central (v0.4). El consumidor debe entregar un archivo temporal privado, inmóvil durante la inspección, y límites vigentes; no usar rutas de usuario no confiables, ni registrar este módulo como fuente.

## Interfaces
- inspectZipCandidate(path,limits): solo metadatos. Conserva contrato v0.4.
- verifyZipContentCandidate(path,limits): verifica metadatos y contenido realmente descomprimido por stream. Devuelve ZIP_CONTENT_VERIFIED_CANDIDATE, actual_unpacked_bytes, content_crc_verified y SHA-256 del archivo. El contenido se descarta, no se extrae al disco ni devuelve filas, no se guarda en Supabase.
- Usa un único descriptor abierto NOFOLLOW/NONBLOCK, valida archivo regular y comprueba tamaño/mtime/ctime antes de devolver. La ruta temporal debe ser controlada por el consumidor; no es una garantía de inmutabilidad criptográfica frente a un escritor concurrente privilegiado.

## Resguardos implementados
- Compara cabecera local y central: firma, flags, método, CRC, tamaños y nombre exacto; exige rangos contiguos y no superpuestos.
- STORE y DEFLATE raw; limita bytes reales y ratio antes de admitirlos; compara longitud efectiva y CRC32, rechaza DEFLATE inválido / bytes sobrantes.
- Reutiliza límites externos de v0.4, sin defaults de negocio.
- No escribe, no adquiere credenciales ni decide licencias. PTE continúa como único adaptador admitido. SUNAT aún requiere transporte, evidencia de licencia y privacidad, formato interior y parser.

## Limitaciones explícitas
ZIP clásico sin descriptor de datos (bit 3), ZIP64, multidisco y otros flags/métodos no compatibles quedan bloqueados. La compatibilidad del ZIP oficial real no está verificada. No inventar formato CSV: podría ser TXT delimitado. CRC no es firma ni prueba de procedencia. Falta timeout de operación de archivo a nivel caller, transporte con cuotas efectivas y parser autorizado; no promover ni declarar seguridad universal.

## Evidencia
Node 22.16.0, prueba local de 18 escenarios sobre blobs Git exactos:
- zip_archive_preflight.mjs: f18daa17cd1ac52292f4a72ba314d5fb48d791c6
- zip_content_verify.mjs: f8902be8c5599dd79f4fdc485ea8f444c2ab572b
- zip_content_verify.test.mjs: 79cf2ab87f1af1c8d74702d83e507408ab9334b1
Comando: node skills/ai_sales_discovery/tests/zip_content_verify.test.mjs.
Fixtures sintéticos; confirmación CI obligatoria. No se descargó ZIP SUNAT ni se modificó BD.
