# M2 lote 2: siete grupos pendientes, siete candidatas

Origen: inventario M2 53 fuentes / 31 obligaciones en docs/nucleo/LF_M2_INVENTARIO_53_31_GRUPOS_20261123.md; SQL SELECT legadas y EKB. Lote previamente FALTA_MIGRAR, sin alterar las 53 fuentes.

| Grupo | Fuentes ID | Candidata | Guard |
|---|---|---|---|
| M2-G05 | 146, 147 | M2L2-C01 | m2l2_intento_materializar_ofertas Y m2l2_modalidades_duplican_deuda_como_ofertas |
| M2-G09 | 157 | M2L2-C02 | m2l2_intento_mostrar_ver_mas_planes Y m2l2_sin_planes_adicionales_autorizados |
| M2-G13 | 171 | M2L2-C03 | m2l2_intento_render_card_oferta Y m2l2_card_estado_visual_incongruente |
| M2-G14 | 172 | M2L2-C04 | m2l2_intento_render_copy_ofertas Y m2l2_copy_incongruente_con_seleccion |
| M2-G16 | 238 | M2L2-C05 | m2l2_intento_cerrar_modal_cuotas Y m2l2_modal_cierre_pierde_seleccion_o_navega |
| M2-G18 | 244 | M2L2-C06 | m2l2_intento_render_plan_modal Y m2l2_primera_cuota_no_destacada_o_ausente |
| M2-G25 | 382 | M2L2-C07 | m2l2_intento_mostrar_cta_oferta_home Y m2l2_copy_promete_simulacion_o_oferta_no_real |

14 hechos lógicos booleanos con tabla_ref y columna_ref NULL, binding Paulo PENDIENTE. 28 casos sintéticos positivo/negativo/borde, 7 mutantes de alcance, pruebas PG17 BEGIN/ROLLBACK y snapshot exacto, EKB de alcance/UI. La fuente legada G05 (146 y 147) queda compuesta en una sola obligación sin transformar modalidades en ofertas. Ningún threshold numérico nuevo. Juicio semántico válido 0 hasta veredicto independiente, no interpretar BLOQUEADA como avance de juicio. No publicar, deprecar, cambiar reglas legadas/REG_CHK_007, IG ni perfiles.
