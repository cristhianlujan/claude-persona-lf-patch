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
  company_id uuid NOT NULL,
  currency_code char(3) NOT NULL,
  PRIMARY KEY (offer_id, company_id)
);

CREATE TEMP TABLE demo_planes (
  plan_id uuid PRIMARY KEY,
  offer_id uuid NOT NULL,
  company_id uuid NOT NULL,
  config_version integer NOT NULL,
  plan_total_amount numeric(18,2) NOT NULL CHECK (plan_total_amount >= 0), -- total de ESTA alternativa
  state_code text NOT NULL, -- valor real se resolverá desde lf_ops.estados_catalogo
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

**Identidad y conciliación:** `offer_id` pertenece a la empresa; cada oferta puede contener muchos `plan_id`. Cuota cero `cuota_num=0` vive en `demo_cuotas`, NO en cabecera del plan. Las cuotas regulares inician en `1`. La suma de `demo_cuotas.amount` de cada plan (incluida cuota cero) debe conciliar exactamente `demo_planes.plan_total_amount` de esa alternativa. No se supone que distintos planes de una misma oferta tengan el mismo monto total; el criterio de precisión está en `B2B-RULE-INSTALLMENT-001` ID422. Esa verificación NO es todavía un validator operativo: `B2B_IMP_VAL_INSTALLMENT_SUM` ID88 tiene `tolerance_policy=PENDING_DECISION` y agrupación física aún sin reconciliar.

**Entrada Excel:** `REFERENCIA_EMPRESA + PLAN` solo relaciona filas dentro del archivo. LF asigna claves internas. No usar número de fila, texto del plan o RUC como PK.

**Fechas:** se calculan desde `PAYMENT_CONFIRMED` para cuota 0, según calendario/ventana por empresa; los vencimientos propuestos previos no se vuelven definitivos hasta el snapshot contractual. No inventar número fijo de días ni usar la fecha del Excel como definitiva para modalidad dinámica.

## Ejemplos, NO límites codificados

- Empresa hipotética A: conjunto permitido `{1,3,6,12}`.
- Empresa hipotética B: conjunto permitido `{1,2,3,4,5,6}`.
- La decisión funcional candidata contempla ampliar el máximo sobre 12 solo si la configuración y autorización empresarial lo permiten. Ningún ejemplo autoriza producción.

## Definiciones diferidas a desarrollo

Claves y tablas reales de ofertas/planes/cuotas; versionado y cambios de plazos; reglas de cobertura de períodos y corte; manejo de estados, pagos, ledger, permisos y snapshot de cronograma; comprobación de fuentes canónicas existentes; migration Train; datos de prueba con rollback y E2E.

**Prohibiciones:** no crear tablas finales con este esquema, no generar constantes frontend desde estos ejemplos y no promover `CANDIDATO` sin controles reales.
