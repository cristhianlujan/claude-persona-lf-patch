# Selector experimental — Paso 1 y arnés del Paso 2

Base PR #3550: `d675a7248ac686049623c7f2c0906504bdfb6f34`.

## Evidencia incluida
- `original/functions/`: siete funciones originales extraídas por lectura y fijadas con SHA-256 en `SOURCE_PIN.json`.
- `original/schema/bootstrap.sql`: extensiones y pgcrypto; `tables.sql` y `constraints.sql`: proyección mínima de seis tablas y restricciones aplicables.
- `original/data/`: seis INSERT depurados; revisar `DATA_MINIMIZATION.md` antes de cualquier redistribución.
- `expected/`: catálogo ORIGINAL y cinco prepare_v2 del ORIGINAL (dos PRODUCTO, dos PROGRAMACION y uno sin canal), cada JSON con huella de su representación `jsonb::text` PostgreSQL.
- `tests/test_parity.py`: arnés fail-closed y comparación de los seis JSON/huellas; pruebas SELECTED, AMBIGUOUS, NO_MATCH, perfil fuera de catálogo, referencia de evidencia inventada, autoridad inyectada y recibo manipulado.

## Ejecución exclusiva de Claude en una DB local nueva
El usuario de PostgreSQL debe tener permiso para crear schemas y extensión pgcrypto. No ejecutar en Supabase.

```bash
export SELECTOR_EXP_DISPOSABLE_DB=YES
export SELECTOR_EXP_TEST_DSN='postgresql://postgres:LOCAL_PASSWORD@127.0.0.1:5432/selector_exp_test_parity'
python3 sandbox/lf_contract_gate_test/programming_agent_four_stage/selector_experimental/tests/test_parity.py
```

El arnés exige opt-in literal, URI localhost, DB cuyo nombre comienza con `selector_exp_test_`, servidor loopback y ninguna tabla previa en public. Crea componentes de ensayo y al salir intenta eliminarlos, comprobando que queden cero relaciones y cero schemas `extensions`. Utiliza `psql` del sistema, no requiere dependencias Python externas.

**Limitaciones**: las huellas de datos minimizados difieren intencionalmente del snapshot completo. La paridad todavía no se ha ejecutado aquí; los controles de seguridad y limpieza también esperan ejecución real. El DDL no incluye columnas ajenas al selector ni FKs de otras tablas, ni reproduce RLS/triggers productivos. No hay variantes `_exp_`: Paso 3 permanece sin iniciar.

**STOP** si falla cualquier comparación o si el servidor no es local. No modificar las referencias expected/ para forzar coincidencia.
