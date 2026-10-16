> **SUPERADO en relación Plan–Oferta.** Este ejemplo histórico mantiene una cardinalidad invertida y no debe utilizarse para programación. La referencia vigente de trabajo es [Excel Completo V5: Plan con múltiples ofertas](B2B_EXCEL_COMPLETO_V5_PLAN_MULTIOFERTA_REFERENCIA_20261016.md). La estructura física final sigue pendiente del desarrollo.

# B2B Cuotas — esquema físico ILUSTRATIVO, NO modelo definitivo

**Estado:** `DEMO_ONLY_NOT_FOR_MIGRATION`. No crea estructuras permanentes ni representa autoridad productiva. El modelo físico final se resuelve durante desarrollo, después de reconciliar carga, ofertas, pagos y asignación empresarial. No copiar estos CREATE TEMP TABLE a una migración.

## Jerarquía de jurisdicción

```text
NEGOCIO LF        dueño de políticas y defaults del producto
   │
   ├── GRUPO corporativo   agrupación y alcance autorizado (NO hereda jurisdicción inversa)
   │      ├── EMPRESA A   parámetros globales solo para empresa A
   │      └── EMPRESA B   parámetros globales solo para empresa B
   └── empresa sin grupo  parámetros propios
          ↓
     PLAN y CUOTAS del ámbito empresarial
          ↓
     Pantallas / asistente / Excel consumen, nunca gobiernan límites
```

Fuente real vigente de pertenencia: `lf_ops.empresas.company_id`, `lf_ops.b2b_corporate_groups` y `lf_ops.b2b_corporate_group_companies`. **Negocio** está por encima de empresa, pero no se sustituye por `company_id` ni se registra un parámetro de empresa como default del negocio. Grupo corporativo NO supone por sí mismo la capacidad de cambiar políticas de sus miembros.

## Entidades de prueba (solo SQL ilustrativo)

```sql
BEGIN;

CREATE TEMP TABLE demo_empresa_plazo_config (
  company_id uuid NOT NULL,
  config_version integer NOT NULL,
  allowed_counts integer[] NOT NULL,  -- conjunto explícito autorizado para ESTA empresa
  max_installments integer NOT NULL, -- tope empresarial autorizado, no límite global del negocio
  minimum_first_regular_days integer NOT NULL, -- tras PAYMENT_CONFIRMED de cuota 0
  effective_from date NOT NULL,
  PRIMARY KEY (company_id, config_version)
);

CREATE TEMP TABLE demo_ofertas (
  offer_id uuid NOT NULL,
  debt_id uuid NOT NULL, -- identidad de deuda ilustrativa: una deuda puede tener varias ofertas alternativas
  company_id uuid NOT NULL,
  currency_code char(3) NOT NULL,
  offer_total_amount numeric(18,2) NOT NULL CHECK (offer_total_amount >= 0),
  PRIMARY KEY (offer_id, company_id)
);

CREATE TEMP TABLE demo_planes (
  plan_id uuid PRIMARY KEY,
  offer_id uuid NOT NULL,
  company_id uuid NOT NULL,
  config_version integer NOT NULL,
  state_code text NOT NULL, -- valor real se resolverá desde lf_ops.estados_catalogo
  UNIQUE (offer_id,company_id), -- ejemplo cuota: cada plan vincula UNA oferta económica propia
  FOREIGN KEY (offer_id,company_id) REFERENCES demo_ofertas(offer_id,company_id),
  FOREIGN KEY (company_id,config_version) REFERENCES demo_empresa_plazo_config(company_id,config_version)
);

CREATE TEMP TABLE demo_cuotas (
  plan_id uuid NOT NULL REFERENCES demo_planes(plan_id),
  cuota_num integer NOT NULL CHECK (cuota_num >= 0),
  amount numeric(18,2) NOT NULL CHECK (amount >= 0),
  due_date date, -- nulo hasta que la fecha sea autoritativa
  PRIMARY KEY (plan_id, cuota_num)
);
-- NO COMMIT: nunca persistir este modelo desde este documento.
ROLLBACK;
```

**Identidad y conciliación:** en este ejemplo una deuda (`debt_id`) puede tener ofertas alternativas con distinto `offer_id`; cada plan de cuotas (`plan_id`) corresponde a su propia oferta económica y monto `demo_ofertas.offer_total_amount` (no es el mismo monto de todas las alternativas). Se muestra `UNIQUE(offer_id,company_id)` solo para ilustrar la distinción económica; la cardinalidad física final deberá reconciliarse con el contrato Cliente VIGENTE. Cuota cero (`cuota_num=0`) es opcional y vive en `demo_cuotas`, NO en cabecera del plan. Es pago inicial activo solo si supera el parámetro candidato de 1 unidad monetaria; cero no se considera activo. Las cuotas regulares inician en `1`. La suma de importes de cuotas efectivas debe conciliar `demo_ofertas.offer_total_amount`. El criterio de precisión está en `B2B-RULE-INSTALLMENT-001` ID422. Esa verificación NO es todavía un validator operativo: `B2B_IMP_VAL_INSTALLMENT_SUM` ID88 tiene `tolerance_policy=PENDING_DECISION` y agrupación física aún sin reconciliar.

**Entrada Excel:** `REFERENCIA_EMPRESA + PLAN` solo relaciona filas dentro del archivo. LF asigna claves internas. No usar número de fila, texto del plan o RUC como PK.

**Fechas:** los ejemplos de ventana de pago son sugerencias sujetas al futuro modelado físico. Si hay cuota 0 activa, un `PAYMENT_CONFIRMED` real puede ser el evento de referencia para estudiar una propuesta de cronograma; si no hay cuota 0 activa, el evento de activación **no está definido**. Se debe modelar la relación entre empresa, deuda, oferta, plan, calendario, ledger, pago y snapshot antes de fijar vencimientos definitivos. No inventar número fijo de días ni asumir que una fecha Excel es contractual.

## Ejemplos, NO límites codificados

- Empresa hipotética A: conjunto permitido `{1,3,6,12}`.
- Empresa hipotética B: conjunto permitido `{1,2,3,4,5,6}`.
- La decisión funcional candidata contempla ampliar el máximo sobre 12 solo si la configuración y autorización empresarial lo permiten. Ningún ejemplo autoriza producción.

## Definiciones diferidas a desarrollo

Claves y tablas reales de ofertas/planes/cuotas; versionado y cambios de plazos; reglas de cobertura de períodos y corte; manejo de estados, pagos, ledger, permisos y snapshot de cronograma; comprobación de fuentes canónicas existentes; migration Train; datos de prueba con rollback y E2E.

**Prohibiciones:** no crear tablas finales con este esquema, no generar constantes frontend desde estos ejemplos y no promover `CANDIDATO` sin controles reales.
