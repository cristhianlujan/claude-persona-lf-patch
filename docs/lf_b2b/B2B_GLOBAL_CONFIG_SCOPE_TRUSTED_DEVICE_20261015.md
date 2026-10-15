# LF Backoffice Empresa — configuración global y jurisdicción (decisión de diseño)

## Jerarquía explícita
1. **Negocio LF**: política central del producto (`lf_ops.politicas_seguridad` ID25); autoridad superior, no es una empresa.
2. **Grupo corporativo**: determina ámbito autorizado de empresas. No obtiene valores empresariales como defaults del negocio, ni cambia políticas por existir una relación.
3. **Empresa**: configuración global **en su propia jurisdicción**, mediante `lf_ops.empresas.company_id`. No asciende a Negocio LF ni modifica otra empresa.
4. **Pantalla, operación y API**: consumidores sin constantes locales como fuente de verdad.

## Duración de dispositivo confiable — una fuente de los límites
- `SEC-B2B-TRUSTED-DEVICE` ID25 (`CANDIDATO`) ya define la lista `[7,15,30,60,90]`, default `30` y el campo de empresa `lf_ops.empresas.trusted_device_duration_days`.
- La validación `B2B_VAL_TRUSTED_DEVICE_DURATION_ALLOWED` (ID103) no debe repetir default ni lista; PR de migración la convierte en consumidora de la política ID25.
- El valor elegido en una empresa solo aplica a esa empresa. No cambia el default del Negocio LF.
- La efectividad del cambio requiere servidor y permisos; el cliente solo presenta alternativas autorizadas. Revocación y cambios requieren auditoría.

## Pantalla de configuración global (NO creada aún)
El owner solicita que la duración pueda administrarse desde una pantalla de **Configuraciones globales**, compartida por los módulos consumidores. No existe hoy un destino de pantalla confirmado para esa función en `lf_ops.pantallas`. `B2B_MENU_CONFIGURACION` existe, pero `pantalla_id` es NULL. `B2B-RULE-CONFIG-001` mantiene por decisión previa la administración de seguridad excluida del autoservicio empresarial, y la política ID25 señala `B2B-ADMIN-001`.

**No mezclar áreas:** la configuración global del **Negocio LF** requiere autoridad del administrador global y no debe colocarse automáticamente en Configuración de una empresa. Si se habilita ajuste empresarial, se resuelve dentro de su jurisdicción con permisos propios. Hace falta reconciliar ubicación UX, perfiles, acciones y decisión previa antes de registrar una pantalla definitiva.

Estado funcional `PENDING_FUNCTIONAL_DEFINITION` solo para la **ubicación física/permissions de UI**, no para los límites ya definidos en la política.

## Aceptación en desarrollo
Lectura dinámica de ID25; validación server-side de valores permitidos; override empresarial autorizado y aislado; empresa A jamás modifica B, grupo no salta permisos, y nunca se concede sesión con token no autorizado. Ejecución de tests y E2E después de integración, sin declarar PASS ahora.
