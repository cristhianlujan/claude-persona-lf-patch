# Contrato de seguridad y privacidad

Juez asociado: `J06_SECURITY_PRIVACY`. Validador: `scripts/validate_security_coverage.py`.

## Claves obligatorias

```text
authentication_required   allowed_profiles        required_permissions
tenant_key                cross_tenant_policy     server_side_enforcement
rls_required              mfa_required            step_up_action
rate_limit_policy         idempotency_required    storage_policy
signed_url_policy
```

## Reglas duras

- Autorizacion validada solo en cliente: falla.
- Mutacion sin autorizacion server-side: falla.
- `tenant_key` ausente: falla.
- `cross_tenant_policy` distinto de `DENY` o `EXPLICIT_ALLOW_WITH_AUDIT`: falla.
- Descarga sensible sin almacenamiento privado: falla.
- URL firmada sin TTL: falla.
- Accion critica sin decision de MFA: falla.
- Mutacion sin decision de idempotencia: falla.

## Aislamiento por empresa

En LF el aislamiento por empresa es obligatorio y no opcional. El filtro por
`tenant_key` se aplica del lado del servidor y se prueba con un caso negativo
cross-tenant en cada historia que lea o escriba datos de empresa.

## Decision, no omision

Si la fuente no define MFA, idempotencia o TTL, la salida registra
`PENDING_DECISION` con el dato minimo faltante. Ausencia silenciosa es falla.
