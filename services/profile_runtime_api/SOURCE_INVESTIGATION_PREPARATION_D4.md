# LF — D4: adaptador inactivo de preparación D1–D3

**Estado:** fuente candidata en GitHub, **sin conexión al dispatcher del worker**, sin despliegue a Hetzner y sin activación para perfiles. No ejecuta un caso de negocio.

**Propiedad canónica:** Supabase. Esta pieza no almacena reglas, fuentes, políticas, permisos, pesos ni estados. El módulo `profile_runtime_api.source_investigation_preparation` acepta un cursor de una conexión confiable ya abierta, llama una única consulta fija y parametrizada:
`SELECT private.fn_lf_source_investigation_prepare_v1(%s, %s) AS preparation`.

Rechaza antes de la llamada el objetivo o presupuesto inválido. Tras la respuesta exige el contrato `LF_SOURCE_INVESTIGATION_PREPARATION_V1`, los seis flags de **no autorización/no efectos**, agotamiento solamente local, un `next_action` conocido, consistencia D3 y conteos de bindings correctos. No acepta filas empresariales ni SQL generado. Ante error de base devuelve un código estable sin exponer excepciones ni credenciales.

El SQL real está en el procedimiento Supabase fusionado en PR #2223. **El adaptador no lo duplica**, no resuelve fuentes por nombre propio y no usa un segundo planificador.

## Verificación técnica

Los archivos exactos de esta rama fueron ejecutados localmente con `PYTHONPATH=.` y `python -m unittest discover -s tests -p 'test_source_investigation_preparation.py' -q`: **16 métodos unittest, sin fallos**, con múltiples subcasos para denegaciones. Incluyen parametrización que impide interpolación SQL, presupuesto y objetivo inválidos, fallos DB redactados, falsificación de permisos/efectos/agotamiento, desalineación de D3 y bloqueo seguro por vigencia.

Esta prueba **no ejecuta Supabase, Hetzner ni información B2B**, y no demuestra una ruta de ejecución empresarial. Toda lectura de negocios requiere fachada invocadora distinta, pertenencia real a empresa, política y permisos vigentes, RLS, límites y recibo verificable en Supabase.

## Integración posterior (no activada)

Para conectar el worker: declarar una operación/capacidad gobernada en Supabase, obtener el enlace autorizado del Router, validar el contrato de entrada y permitir solamente esta etapa de **preparación**. La activación y el dispatcher deben quedar bloqueados hasta que el plano de datos D2, las pruebas reales de tenant y el benchmark se admitan. No agregar rutas especiales por tabla ni conceder permisos al modelo.

**Excel:** visualización únicamente, no registro ni fuente normativa.
