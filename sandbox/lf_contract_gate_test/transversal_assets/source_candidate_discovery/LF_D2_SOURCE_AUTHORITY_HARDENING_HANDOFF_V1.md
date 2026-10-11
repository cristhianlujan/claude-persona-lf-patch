# LF — Contrato de autoridad de activos y camino de cierre de D2

## Defecto confirmado y contención
El catálogo `public.lf_activos` aceptaba un INSERT de `authenticated` con `metadata.admission_status="VIGENTE"` y `approved_by_ref` autodeclarado; el probe se revirtió. Además, `anon` y `authenticated` tenían GRANT de `TRUNCATE`, `TRIGGER` y `REFERENCES` no necesarios.

La migración retira `INSERT/TRUNCATE/TRIGGER/REFERENCES` a PUBLIC/anon/authenticated y elimina solo la política `lf_activos_authenticated_insert`. Mantiene `SELECT` autenticado, escrituras de service_role/postgres, y todas las demás políticas. No toca información existente ni RLS de cargas.

**Prueba de regresión**: rollback del SQL original de Git: cliente no puede insertar una ficha autodeclarada; el servidor sí puede insertar ficha `CONTRACT` ordinaria; `SELECT` autenticado y permisos del servidor intactos; política SELECT conservada; ninguna fixture sobrevive al ROLLBACK.

## Decisión de gobernanza — Unidad 7

1. **D1** descubre candidatos y el generador D2 observa esquemas, pero no publica permisos ni valores VIGENTE.
2. **Admisión de binding** no se obtiene de `metadata.admission_status` ni de `approved_by_ref` en JSON suministrado por clientes. Requiere decisión de autoridad verificable/receipt persistido, política y esquema actuales, operación y fachada permitidas, allowlists tipadas y bounded.
3. **NO autorizar el runtime** por estado estructural ni por PR: solo un recibo bajo identidad/tenant real de unidad 8 puede dar acceso a filas.
4. **Salida de construcción U7**: código del ciclo candidato→aprobado/rechazado más verificador de autoridad, incluyendo prueba positiva estructural y negativa de falsificación. No depende de tener usuarios B2B reales. La demostración tenant/permiso y RLS pertenece a U8, y el ledger de lectura a U9.
5. Este macrolote corrige únicamente el escritor genérico del catálogo. Hasta incorporar verificación independiente del recibo al evaluador D2, toda pretensión de `VIGENTE` continúa bajo política **NO ADMITIR FUENTE AL RUNTIME**.

No usar Excel para autoridad, reglas ni recibos. No se modifica PASE ni se inventa un registro fuente de otra base. Runtime permanece inactivo.
