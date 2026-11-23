# M4B OTP, Rate limit y sesiones — sublote CANDIDATA V1

Fuente M4 112/112 del PR #4663, fuentes legadas consultadas en Supabase RO, resguardos y EKB. 8 obligaciones seleccionadas sin decisión nueva.

| Candidata | ID legado | Familia | Guard |
|---|---:|---|---|
| M4-B01 | 14 | SESSION | m4b_intento_reanudar_otp_pendiente AND m4b_otp_pendiente_sesion_expirada |
| M4-B02 | 15 | SESSION | m4b_intento_retomar_onboarding AND m4b_sesion_expirada_con_precarga |
| M4-B03 | 18 | SESSION | m4b_intento_mutacion_sesion AND m4b_onboarding_completado |
| M4-B04 | 30 | RATE_LIMIT | m4b_intento_reenvio_backend AND m4b_cooldown_backend_otp_activo |
| M4-B05 | 63 | RATE_LIMIT | m4b_intento_habilitar_reenvio_ui AND m4b_timer_otp_ordinario_no_vencido |
| M4-B06 | 64 | RATE_LIMIT | m4b_intento_reenvio_tras_agotamiento AND m4b_cooldown_agotamiento_reenvios_activo |
| M4-B07 | 65 | RATE_LIMIT | m4b_intento_cambiar_numero_inline AND m4b_limite_cambio_inline_excedido |
| M4-B08 | 123 | SECURITY | m4b_intento_captcha_paso_otp AND m4b_captcha_adicional_otp_presentado |

16 hechos booleanos lógicos nuevos, todos sin tabla_ref ni columna_ref. Límites y ventanas se leen de public.lf_global_config mediante los parámetros AUTH nombrados en cada descripción; no existen cifras operativas fijas. El runtime y sus bindings corresponden a Paulo, no certificados aquí.

PG17 prueba SQL exacto dentro de BEGIN/ROLLBACK, snapshots completos antes/después y verifica 32 casos, ocho mutantes de guard, 17 regresiones. La función evaluar devuelve BLOQUEADA sin juicio independiente; se computa 0% de juicios válidos. Se registra un hallazgo EKB en la misma migración. Prohibido publicar, deprecar, tocar legadas, IG, perfiles, lectores o REG_CHK_007.
