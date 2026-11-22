# SALY Ventas — Captura multifuente, concurrencia y evaluación semántica
**Estado:** CANDIDATO / NO HABILITADO / esquema SQL sin desplegar. **Negocio:** SALY U07; componentes reutilizables entre negocios con política separada. **Fecha:** 2026-11-22.
**Fuente de resguardos:** `LF_resguardos_construccion.md` A1–A14, B1–B32. **Reglas de ruta:** `skills/ai_sales_discovery/SKILL.md`, `docs/ai_sales/candidate/AI_SALES_CROSS_BUSINESS_ADAPTER_BINDING_V1.md`. **No crear Router o perfil exclusivo por marca**.

## Objetivo acordado
1. Piloto histórico de 2 meses: **2026-09-22 00:00:00 America/Lima hasta 2026-11-22 23:59:59 America/Lima**; después ampliar a 12 meses (**2025-11-22 a 2026-11-22**) solo si superó cobertura, derechos, continuidad, conexión y tiempos medidos. Almacenar resultados reales en tablas SALY únicamente con operación de ingesta gobernada y readback.
2. **Duplicado intracanal**: misma publicación o mismo hecho/afirmación por fuente => OMITIR registro del duplicado y contar omisión en el recibo. Mismo `external_ref` con hash distinto => conflicto de versión; no sobrescribir.
3. **Duplicado intercanal**: conservar **un evento canónico**; NO volver a guardar el mismo hecho. Registrar vínculo de concurrencia con canal, `external_ref`, URL, evidencia de homologación y referencia al canal de origen. Si una fuente confirma una fase nueva (ANUNCIADO -> REALIZADO), conservar las dos afirmaciones con sus fechas y procedencias. No confundir publicidad repetida con dos iniciativas.
4. Continuar con fuentes **webs corporativas, diarios, revistas, foros, medios digitales**; LinkedIn tiene adaptador separado y puerta de derechos/condiciones de plataforma. Por defecto no capturar comentarios ni datos personales de terceros; no perfilado individual de trabajadores, estudiantes o menores.
5. La evaluación semántica se realiza **después** de converger fuentes, no una evaluación independiente por canal. Mantener alternativas, contradicciones, hipótesis y trazabilidad; no inventar probabilidades de compra.

## Secuencia gobernada (pasos internos U07-SOC-01..13; no registrar nuevos steps/substeps nativos por analogía)
| Paso | Entrada | Acción y evidencia | Gate/salida |
|---|---|---|---|
| SOC-01 Admisión | Router ACT-0001, negocio real, operación y RUN | Resolver política y fuente autorizada del catálogo, scope del piloto, límites de transporte, lease | Sin autoridad real: `BLOCKED_NO_OPERATION`; no usar ejecuciones de otra función |
| SOC-02 Identidad | Empresa, perfil FB/IG/medio | Resolver entidad jurídica y cuentas oficiales con URLs de su web/registro; guardar evidencia | `IDENTITY_UNVERIFIED` -> candidato en cuarentena |
| SOC-03 Derechos | Plataforma, licencia y uso comercial específico | Revisar condiciones vigentes, permiso/API, atribución, minimización, retención | `RIGHTS_NOT_VERIFIED` bloquea **persistencia y captura automatizada productiva**, no se convierte en PASS por acceso público |
| SOC-04 Ventana | `window_start/end`, reloj único | Piloto 2m, luego 12m explícito; deduplicar cortes, timezone Lima/UTC | No inferir fecha por texto del evento ni por ID |
| SOC-05 Transporte | Adaptador dedicado `FACEBOOK`, `INSTAGRAM` o medio | Fetch autorizado paginado, timeout y cuotas config, hash, `cursor_checkpoint`, intentos/backoff, `elapsed_ms` por request, `source_end` | Login/rate-limit/cursor detenido: parcial, conservar checkpoint, NO cerrar cobertura |
| SOC-06 Verificación | Registro y metadatos | Autor, URL, fecha publicada, contenido asociado; detectar body ≠ OG, errores, publicaciones antiguas de otro año | Post sin fecha: `HOLD_NO_DATE`; contaminación: `CONTENT_MISMATCH`; nada inventado |
| SOC-07 Homologación | Publicación verificada | Identidad empresarial, extracción de hechos y estado ANUNCIADO/REALIZADO/IMPLEMENTADO/NO_DETERMINADO, `event_key` candidato | `event_key` coincidente requiere revisión o homologador autorizado, no asumir equivalencia semántica |
| SOC-08 Deduplicación origen | `(business,source,external_ref,hash,event,claim)` | Dos capas: idem mismo post y claim mismo canal; sin doble inserción | `DUPLICADO_CANAL_OMITIDO`; digest diferente mismo ID => conflicto |
| SOC-09 Concurrencia | Claim, evento canónico | Relación `MISMO_HECHO/COMPLEMENTA/CONTRADICE/POR_REVISAR` con canal original y de confirmación | Solo un hecho, múltiples referencias; contradicción no se borra |
| SOC-10 Persistencia | Payload mínimo, RUN/operación real | Única puerta de escritura server-bound; tablas SALY, ACL, transacción, locks/idem, recibo SHA y conteos | Readback independiente por RUN, fuente, ventana y hash; sin writer no hay escritura |
| SOC-11 Expansión fuentes | RSS/API/licencia/web noticias, revistas, foros, digitales, LinkedIn | Adaptador por origen; autor/editor, fecha, URL canónica y alias, región, empresa, derechos, duplicados sindicados | Medios ajenos: no asumir derechos para copiar artículos; guardar metadatos y hechos derivados permitidos |
| SOC-12 Convergencia y semántica | Eventos canónicos + fuentes + contradicciones | LLM identifica patrones/H1..Hn, citas exactas, hipótesis alternativas, conductas no obvias; validador determinista | Sin soporte de evidencia => RECHAZADA; no porcentajes predictivos sin historia |
| SOC-13 Resultado | Perfil, oportunidades y evidencias | Guardar snapshot en tablas SALY, resultado V1 explorable, contraevidencias, hipótesis por validar en campo | Cierre solo si procedencia, calidad, derechos y BD readback coinciden; no activar contacto |

## Capturas 2026-11-22 — evidencia medida de acceso, NO producción
- Instagram público `https://www.instagram.com/p/Dc2QaA3IHTb/` publicó el 2026-09-04 UTC según metadatos (3/09 Lima), lectura inicial **4342.76 ms** y repetición **4012.46 ms**.
- Instagram público `https://www.instagram.com/p/DdZ66MRoDLD/` publicó el 2026-09-17 UTC, lectura **5859.76 ms** y repetición **4975.74 ms**.
- Facebook vídeo institucional `https://www.facebook.com/sanfranciscocollege/videos/-que-comience-la-fiesta-deportiva-este-s%C3%A1bado-12-de-setiembre-desde-las-830-am-n/1731691128103725/`: **1626.41 ms** y repetición **2511.49 ms**. El campo `published_date` fue **NULL** y cuerpo textual no correspondía al título OG; se rechaza usarlo como post fechado.
- Facebook video `.../1658497724636471/`: **1961.32 ms**, su texto OG habla de `ONEM2023`; NO sirve para 2026 aunque el buscador lo devolvió.
- `https://diariocorreo.pe/edicion/ica/ica-san-francisco-college-logro-medalla-en-basquet-masculino-de-los-juegos-escolares-nacionales-2026-noticia`: 2026-11-01, **5710.57 ms**.
- Instagram perfil web devuelve 12 entradas actuales, pero la paginación en navegador público encontró login. Acceso a URL individual vieja ≠ iteración paginada completa; no se acreditan meses completos.
- La medida es de latencia por recurso devuelta por el servicio de lectura, NO tiempo de histórico completo, throughput productivo ni tiempo de escritura SQL.

## Persistencia: contrato candidato
- Fuente maestra y derechos: `saly.ventas_discovery_catalogo` ya existente; NO copiar decisión de licencia a un segundo catálogo.
- Nuevas tablas propuestas `saly.ventas_social_runs_v1`, `eventos_v1`, `publicaciones_v1`, `afirmaciones_v1`, `concurrencias_v1`, `evaluaciones_v1`, `eval_soportes_v1`; ver migración candidata separada.
- Control duplicados en dos niveles: uniqueness en BD + transacción en el writer que deja fuera duplicados semánticos intracanal; cross-channel solo links de concurrencia.
- ACL sin GRANT y RLS habilitada; no hay writer en la migración. El único writer se implementa en lote posterior usando la **operación gobernada existente** y READBACK; nunca DML cliente ni migra lotes de publicaciones con DDL.
- Nunca introducir contenido de menores ni datos sensibles de empleados. En medios con derechos no verificados, conservar solo enlaces y metadatos de investigación fuera del destino comercial hasta la admisión de derechos.

## Pendientes y bloqueo de cierre
1. Autoridad de Meta y derechos de capturas comerciales/retención todavía no acreditada; una búsqueda pública no acredita permisos (ver política Meta).
2. No existen `FACEBOOK` ni `INSTAGRAM` en el catálogo SALY ni operación/puerta de ingesta social enlazada; instalar esquema en un PR por Train + registrar fuentes/derechos por ruta gobernada, no por SQL manual.
3. No existe una paginación continua verificada de dos meses; test de URLs antiguas no demuestra cobertura total. Mantener `SOURCE_END_UNVERIFIED` y checkpoint.
4. SQL requiere PG17 aislado + caso positivo/negativo + ROLLBACK; pruebas Python NO equivalen a PG17.
5. Las pruebas semánticas candidatas no comprueban precisión externa. Validar contra muestra ciega y feedback comercial antes de activar decisiones automáticas.
6. No declarar nada almacenado en Supabase hasta READBACK de tablas, RUN y SHA; un PR creado no es un despliegue.

## Prueba local reproducible
`python -m unittest -v test_social_convergence_v1.py` — 24/24 en entorno Python local. Cubre replay, conflicto, intra/intercanal, complemento, identidad, rights autoasignados no autorizados, falta de fechas, URLs, concurrencia real en hilos y referencias semánticas inválidas.