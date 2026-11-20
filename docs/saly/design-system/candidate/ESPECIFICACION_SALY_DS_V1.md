# SALY_DS_V1 — Especificación candidata gobernada

**Producto:** Saly · App Cliente  
**Versión:** `1.0.0-candidate.1`  
**Estado del paquete:** `CANDIDATO_GOBERNADO_NO_REGISTRADO`  
**Autoridad:** las decisiones aprobadas de Saly y la aprobación visual del Home; no reemplaza el repositorio ni la fuente canónica en Supabase.  
**Alcance de la solicitud:** formalizar el Design System para herencia de tokens. No incluye implementación móvil ni cambios a LF.

## 1. Base aprobada vs. propuesta

| Elemento | Estado | Evidencia |
|---|---|---|
| Card blanca en Home, monto navy protagonista, CTA verde | Aprobado visualmente | Conversación Saly, 2026-11-07; `evidencia_home_visual_aprobado.png` |
| Home sin sueldo, sin ilustraciones de billetera, cálculo en detalle secundario | Aprobado visualmente | Iteraciones Saly |
| Slots de fecha de descuento, estimado, explicación de disponible | Aprobado visualmente | Iteraciones Saly |
| Plus, Rewards y Beneficios separados | Aprobado visualmente | Iteraciones Saly |
| Códigos HEX exactos del paquete | **Candidato** | Extraídos como aproximación; falta fuente de marca / prueba QA |
| Font Inter, tamaños, espaciados, radios y responsive | **Candidato** | Diseño propuesto; sin especificación aprobada |
| Catálogo oficial en Supabase | **Sin registro** | Conector de lectura, sin transporte gobernado de escritura |

## 2. Jerarquía de tokens y herencia

```text
SALY_DS_V1 (no importa tokens LF)
  ├─ Core: color / typography / spacing / radius
  ├─ Semantic: action.primary, text.primary, surface.card, module.*
  ├─ Component: CARD_DISPONIBLE, CTA_PRIMARY, SUMMARY, DISCOVERY, BOTTOM_NAV
  ├─ Themes: SALY_LIGHT (base)
  ├─ CO_BRANDING (override de marca sujeto a contrato)
  └─ WHITE_LABEL (brand + releases aislados por empresa)
```

**Regla:** no se admiten valores HEX hardcodeados en pantallas consumidoras; los componentes solo consultan alias semánticos. Nunca compartir identidad Saly con `lf_design`.

## 3. Contrato funcional del Home

- Card principal = `Disponible para adelanto` + `máximo retirable ahora` + `Solicitar adelanto`.
- `generado`, `permitido`, `saldo disponible` y `máximo retirable` son diferentes. La cifra pública utiliza este último (`SALY-DEC-041`).
- El sueldo **nunca** se muestra en Home ni en el detalle del disponible.
- La explicación se abre desde `Mi disponible` en la franja secundaria, no dentro de la card.
- Datos de fecha/importe se muestran solo si existen y son verificables; el `cutoff` no se presenta como fecha de descuento (`SALY-DEC-043`).
- Se admite `LINEAR`, `STEPS`, `INSTANT`; `VARIABLE_UPLOAD` es fuente base y no un cuarto motor (`SALY-DEC-040/046`).
- El detalle de cálculo muestra únicamente la política que aplica al usuario y una traza útil, no todas las opciones.
- Saly Plus no incrementa el máximo asignado al periodo (`SALY-DEC-049`).
- Rewards no premia la inactividad ni castiga a quien no usa Saly. Los puntos no se garantizan hasta definir el programa.
- En bloqueos no mostrar saldo como inmediatamente retirable (`SALY-DEC-044`).

## 4. Componentes y estados

- `SALY_CARD_DISPONIBLE_V1`: AVAILABLE, ZERO, BLOCKED_DISPOSAL, PENDING_CALCULATION, ERROR_DATA.
- `SALY_CTA_PRIMARY_V1`: DEFAULT, PRESSED, FOCUS_VISIBLE, DISABLED, LOADING.
- `SALY_FINANCIAL_SUMMARY_V1`: 2 métricas condicionales + enlace `Mi disponible`; adaptar en pantallas estrechas sin comprimir.
- `SALY_DISCOVERY_TILE_V1`: identidades independientes Plus/Rewards/Beneficios.
- `SALY_BOTTOM_NAV_V1`: Inicio / Historial / Explorar / Perfil.

## 5. Requisitos QA

1. Contraste mínimo WCAG 2.2 AA: texto normal >= 4.5:1, controles e íconos funcionales >= 3:1.
2. No usar `#F6B400` sobre blanco como texto ni icono funcional; para icono candidato se propone `#9D6800` sobre `#FFF9E9` (AA), sujeto a validación de marca.
3. Estados error, focus, loading y disabled revisados en Home y Solicitud.
4. Targets táctiles >= 44px de tamaño de diseño candidato; ajustar al estándar aplicable en plataforma nativa.
5. Screenshot en 320, 360, 390 y 430 px; sin overflow del monto, CTA o la tercera celda.
6. Escalado dinámico de texto, soporte lectores de pantalla, reducción de movimiento, controles de privacidad.
7. No cambiar montos por retoque de diseño. Datos de ejemplo no son una simulación financiera.
8. Token alias resoluble, sin loops, sin duplicados; `SALY_LIGHT` no hereda marca LF.
9. Cambios de token aplican versionados; exigir inspección de componentes afectados y readback de al menos dos pantallas.

## 6. Registro gobernado solicitado (NO ejecutado)

```text
SOLICITUD SALY
  → router (capacidad/producto y autoridad verificados)
  → perfil dueño de diseño / operación de creación o actualización
  → validación normativa / decisión / paquete
  → transporte gobernado (sin SQL directo no autorizado)
  → catálogo SALY design system (ubicación física por resolver)
  → readback + juez + atestación + cierre
```

**Bloqueo real:** el conector Supabase disponible en esta sesión es de solo lectura. No se encontró una operación de escritura de Saly verificable y autorizada; tampoco una tabla física `saly_design` existente. No crear registros en `lf_design` ni usar el router LF para eludir el aislamiento.

**Destino lógico propuesto, no físico asumido:** `SALY_DS_V1` con entidades `design_systems`, `color_tokens`, `semantic_tokens`, `typography_tokens`, `spacing_tokens`, `component_tokens`, `theme_bindings`, `visual_decisions`, `qa_receipts`. La implementación del catálogo deberá reconciliar el modelo actual, no duplicarlo arbitrariamente.

## 7. Condiciones de activación y cierre

- Revisión de identidad visual Saly y HEX; aprobación humana explícita de valores fuente.
- Ruta de escritura gobernada para Saly verificada y registrada.
- Insert / upsert versionado con estado inicial `CANDIDATO`, no `VALIDADO` por defecto.
- Readback de IDs, versión, trazabilidad y objetos; validación de juez.
- Evidencia QA y aprobación final para `ACTIVO`.

**NO-GO:** No declarar formalmente registrado, heredable en runtime ni implementado antes de superar estos controles.
