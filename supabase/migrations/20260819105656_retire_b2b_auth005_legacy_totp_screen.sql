update lf_ops.pantallas
set activa=false,
    descripcion='Pantalla TOTP retirada del flujo operativo. Se conserva únicamente como trazabilidad histórica/legacy del diseño anterior; no debe recibir navegación activa ni implementarse como ruta operativa. El segundo control vigente para perfiles no administradores es LF_EMAIL_OTP.',
    objective='Conservar trazabilidad histórica del diseño TOTP previo sin formar parte del flujo operativo B2B.',
    updated_at=now()
where id=55 and codigo='B2B-AUTH-005';