---
name: creative-factory-standalone
description: Orquesta la composición gráfica de revisión reutilizando el compilador, adaptador por negocio y verificador de transporte existentes, sin invocar Router, perfiles ni generación de producción.
---

# Fábrica Digital — skill autónoma v0.1 (REVIEW_ONLY)

## Alcance y activación

La skill puede invocarse directamente por CLI con un **paquete congelado** y archivos
locales. NO ejecuta ni llama Router, perfiles, RUN de perfil, modelos, proveedores,
Supabase ni aprobaciones. No se registra en el selector de perfiles durante este lote.
No reemplaza ni duplica `SALY_VISUAL_CONTEXT_INVENTORY`, `SALY_APP_VISUAL_PROBE`,
`adapter_saly_review_v1`, `native_transport_capture_v1` o `compositor_core_v1`.

**Estado actual:** demostrable con SALY usando un paquete L2C de revisión y un
cuerpo gráfico **sintético**. No admite cuerpos declarados como resultados de GPT Native
sin origen autenticado. Sin adaptador específico no se ejecutan LF ni negocios nuevos.

## Contrato de entrada

`CREATIVE_SKILL_STANDALONE_REVIEW_V1`, modo `COMPOSE_REVIEW_ONLY`:
- `business_code`: código del negocio declarado en el input aislado. No confiere permisos.
- `packet_path` + `packet_sha256`: paquete inmutable con su hash **de bytes**.
- `logo_path`, `fonts_path`, `body_path`: fuentes y cuerpo local.
- `body_origin=SYNTHETIC_REVIEW`: no equivale a respuesta del proveedor.
- `output_dir`: directorio **nuevo** para resultado y recibo técnico.

No recibe perfil, Router, skill de inventario, credenciales, write authority ni
instrucciones para omitir validaciones. El esquema del paquete SALY
(`SALY_WORK_PACKET_L2C_V1`) se verifica contra el adaptador registrado. Un código
LF/futuro nunca reutiliza los datos de SALY como sustituto.

## Flujo obligatorio

1. Validar modo, negocio y campos exactos. Seleccionar adaptador autorizado;
   si falta, `SKILL_BUSINESS_ADAPTER_NOT_AVAILABLE`.
2. Leer el paquete como bytes locales (sin red) y comprobar su hash, versión y
   permisos `REVIEW_ONLY`.
3. Reutilizar `native_transport_capture_v1.sealed_envelope` para comprobar
   prompt literal, adjuntos, item, contrato y SHA; **no enviar**.
4. Reutilizar `adapter_saly_review_v1.from_packet` para materializar en un
   directorio temporal solo SVGs de fuente con SHA y resolver tokens, logo y
   tipografía del contrato. No inventar paleta, copy ni plantilla.
5. Reutilizar `compositor_core_v1.compose` con el cuerpo sintético en slots
   autorizados; producir dos composiciones y compararlas para determinismo.
6. Escribir `composition_review.png` y `receipt.json`; reabrir PNG, comparar
   bytes/píxeles y registrar hashes. La entrega contiene solo esos dos archivos.
7. Cualquier error impide la publicación y devuelve código específico.
   No modificar artefactos previos.

## Resultado y límites de QA

`LOCAL_TECHNICAL_REVIEW_PASS` solo acredita revisión técnica determinista:
hashes, integridad, geometría, aislamiento de áreas, reproducibilidad y readback.

El recibo SIEMPRE declara:
`native_transmitted=false`, `provider_receipt=null`,
`semantic_qa=NOT_EVALUATED`, `production_approved=false`,
`image_generation_allowed=false`, `router_invoked=false`,
`profile_invoked=false`, `database_written=false`.

No elevar a `QA_PASS`, `NATIVE_DELIVERED` ni `RENDER_AUTHORIZED`.
Un juicio visual/semántico independiente y la recepción del proveedor requieren
contratos y evidencias separados, fuera del alcance autónomo actual.

## Ejecución y prueba

```bash
PYTHONPATH=sandbox/creative_factory \
  python sandbox/creative_factory/skill_run_review_v1.py --request /ruta/request.json
PYTHONPATH=sandbox/creative_factory \
  python -m unittest -v sandbox/creative_factory/test_skill_run_review_v1.py
```

Pruebas: positivos, determinismo, no sobrescritura, aislamiento SALY/LF/futuro,
fuentes y tipografías por SHA, mutación de prompt y adjuntos, intento de activar
render, logo alterado, invasión de CTA, JSON duplicado, symlinks, salida no
autorizada y ausencia de efectos de Router/perfiles.

## Extensibilidad

La skill es **una sola** para múltiples negocios. Cada negocio adicional aporta
su contrato fuente y un adaptador probado; el motor, los tests de transporte,
compositor, recibo técnico y QA permanecen compartidos.

Hasta contar con adaptador y pruebas contractuales, la ausencia de fuentes
se trata como **bloqueo**, no como permiso para consultar reglas de otro negocio.
Para integrar posteriormente Router y perfiles se requiere otro lote; aquí no
se implementan ni modifican.
