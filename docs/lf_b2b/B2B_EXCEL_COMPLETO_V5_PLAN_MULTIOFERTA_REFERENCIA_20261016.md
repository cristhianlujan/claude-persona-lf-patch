# LF Backoffice Empresa — Excel Completo V5: Plan → Ofertas alternativas

**Fecha de decisión:** 2026-10-16. **Estado:** `CANDIDATO`, sujeto a Train, ledger/readback e implementación posterior. Este documento prevalece sobre los ejemplos anteriores que tenían la relación invertida, **solo en el ámbito de modelado ilustrativo**. No autoriza nueva estructura persistente de BD ni altera `CLIENT_APP_SHELL`.

## Decisión funcional

- **Plan A** puede tener ofertas A1 de 3 cuotas, A2 de 6 cuotas y A3 de 9 cuotas. El cliente podrá seleccionar **como máximo una** de esas alternativas.
- **Plan B** puede tener solo oferta B1 y el cliente puede seleccionarla **además** de la única oferta elegida de A.
- Cada **OFERTA** tiene su propio monto de oferta, número de cuotas, cuota 0 cuando aplique, y cronograma; no comparte sus importes con las alternativas de su mismo Plan.
- `total_savings` y resumen de pago conjunto se calculan solo sobre ofertas efectivamente seleccionadas, mediante quote server-side, nunca como suma de alternativas no seleccionadas ni descuento inferido en frontend.
- No cambiar por este lote la cardinalidad implementada en el portal Cliente ni su checkout: requiere reconciliación de modelos y validación E2E en su dominio.

## Cambios de contrato — Excel Completo V4 → V5

La estructura de hojas existente **se conserva**, agregando solo `OFERTA` a cada una:

- `OFERTAS_PLANES`: `... REFERENCIA_EMPRESA ... PLAN | OFERTA | MONTO_PLAN | N_CUOTAS ...`
- `CRONOGRAMA`: `REFERENCIA_EMPRESA | PLAN | OFERTA | CUOTA | MONTO`

La nueva unión de filas dentro de **un mismo archivo/lote y empresa** es:
`(REFERENCIA_EMPRESA, PLAN, OFERTA)`.

**OFERTA no es `offer_id` ni un identificador canónico.** Es una referencia local declarada por quien prepara el Excel. LF genera los IDs internos de plan, oferta y cuota según el modelo definitivo, y debe validar que la referencia no sea ambigua dentro del archivo.

| REFERENCIA_EMPRESA | PLAN | OFERTA | N_CUOTAS | MONTO_PLAN | Ejemplo |
|---|---|---|---:|---:|---|
| DEUDA-001 | A | A1 | 3 | 1200.00 | Una alternativa del Plan A |
| DEUDA-001 | A | A2 | 6 | 1260.00 | Segunda alternativa del Plan A |
| DEUDA-001 | A | A3 | 9 | 1350.00 | Tercera alternativa del Plan A |
| DEUDA-001 | B | B1 | 1 | 1150.00 | Oferta única del Plan B |

*Montos simulados solo para ilustrar el cruce; no son parámetros, descuentos aprobados ni cuotas reales.*

Ejemplo de cronograma local para la **oferta A1**:

| REFERENCIA_EMPRESA | PLAN | OFERTA | CUOTA | MONTO |
|---|---|---|---:|---:|
| DEUDA-001 | A | A1 | 0 | 120.00 |
| DEUDA-001 | A | A1 | 1 | 360.00 |
| DEUDA-001 | A | A1 | 2 | 360.00 |
| DEUDA-001 | A | A1 | 3 | 360.00 |

Suma oferta A1: 120 + 360 + 360 + 360 = 1200. La cuota 0 puede no estar o tener cero, y **no es pago inicial activo cuando su importe no supera el umbral de la política candidata (actualmente 1)**. No inferir de aquí activación automática del plan.

## Validaciones antes de desarrollar

1. En Excel Completo V5, `OFERTA` debe estar presente en las dos hojas para cada alternativa; faltante o vacío → error accionable por fila/grupo.
2. La combinación `REFERENCIA_EMPRESA + PLAN + OFERTA` identifica **una alternativa** dentro del alcance de empresa y lote. Los duplicados de cabecera/definiciones contradictorias no se fusionan.
3. Cada fila de `CRONOGRAMA` debe corresponder a **una única alternativa** registrada en `OFERTAS_PLANES`. No asociar cuotas a dos ofertas.
4. `N_CUOTAS` debe conciliar el número de cuotas regulares 1…N del **grupo completo**, independiente de cuota 0, con cantidades permitidas por empresa.
5. La suma de montos del mismo grupo, cuota 0 cuando corresponda más cuotas regulares, debe conciliar `MONTO_PLAN` de esa oferta. No sumar A1+A2+A3.
6. Los importes y descuentos del cliente se derivan exclusivamente del quote server-side sobre su selección; no confundir `MONTO_PLAN` con precio final (tasas/comisiones, etc.).
7. Excel Asistido conserva su contrato de base y no exige referencias `OFERTA` como dato previo.
8. El archivo V4 se conserva como evidencia histórica; las cargas futuras con ofertas múltiples deben utilizar V5 una vez que se implemente y habilite. **No existe conversión automática V4→V5 aprobada.**
9. Las fechas actuales son sugeridas y quedan `PENDING_FUNCTIONAL_DEFINITION` hasta modelar empresa/calendario/eventos de cobro/ledger/snapshot.
10. La estructura canónica de las tablas físicas y las relaciones finales se define en la etapa de programación. Este contrato Excel no las crea.

## Ejemplo de relaciones, NO DDL definitivo

```text
EMPRESA / DEUDA (referencia empresarial)
  ├─ PLAN A
  │    ├─ OFERTA A1 (3 cuotas) ── CRONOGRAMA A1
  │    ├─ OFERTA A2 (6 cuotas) ── CRONOGRAMA A2
  │    └─ OFERTA A3 (9 cuotas) ── CRONOGRAMA A3
  └─ PLAN B
       └─ OFERTA B1 ── CRONOGRAMA B1

SELECCIÓN CLIENTE: A2 + B1 → cotización de pago y ahorro conjunto
```

**Fuentes:** `lf_ops.reglas` 617,620,654,618; `lf_ops.campos_validaciones` 88; `REG_CLIENT_HOME_INSTALLMENT_PLAN_SELECTION_001` y `REG_CLIENT_HOME_MULTI_OFFER_001` se inspeccionaron en solo lectura para detectar el gap entre dominios. `LF_DS_V1` no aplica a este contrato de datos.

**Criterio de cierre:** aplicar migración por Train y verificar V5 registrado en Supabase. La puesta en producción del importador y checkout requiere su propio proceso de programación, permisos, validaciones, errores descargables y E2E; no equivale a este registro de reglas.
