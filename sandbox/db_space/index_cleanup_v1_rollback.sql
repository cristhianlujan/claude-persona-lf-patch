-- DB-SPACE / PR-IDX-1 exact rollback.
-- Execute only with explicit owner approval if PR-IDX-1 has been applied.
-- Definitions captured from pg_get_indexdef on LF_SUPABASE_SANDBOX before authoring.

CREATE UNIQUE INDEX uq_lf_operation_execution_steps_execution_order ON public.lf_operation_execution_steps USING btree (execution_id, step_order);
CREATE UNIQUE INDEX uq_lf_operation_steps_operation_step ON public.lf_operation_steps USING btree (operation_code, step_id);
CREATE UNIQUE INDEX uq_lf_operation_steps_operation_order ON public.lf_operation_steps USING btree (operation_code, step_order);
CREATE UNIQUE INDEX uq_lf_operation_judges_operation_judge ON public.lf_operation_judges USING btree (operation_code, judge_code);

CREATE INDEX idx_rp_pantalla ON lf_ops.reglas_pantallas USING btree (pantalla_id);
CREATE UNIQUE INDEX ux_perfiles_permisos_numeric ON lf_ops.perfiles_permisos USING btree (profile_id, permission_id);
CREATE INDEX idx_campos_pant_pant ON lf_ops.campos_pantallas USING btree (pantalla_id);
CREATE UNIQUE INDEX ux_user_number ON lf_ops.empresa_usuarios USING btree (user_number);
CREATE UNIQUE INDEX ux_usuarios_perfiles_numeric ON lf_ops.empresa_usuarios_perfiles USING btree (user_id, profile_id);
CREATE UNIQUE INDEX ux_usuarios_permisos_numeric ON lf_ops.empresa_usuarios_permisos USING btree (user_id, permission_id);
CREATE UNIQUE INDEX ux_company_number ON lf_ops.empresas USING btree (company_number);
CREATE UNIQUE INDEX ux_trace_number ON lf_ops.errores_ocurrencias USING btree (trace_number);
CREATE UNIQUE INDEX ux_transiciones_numeric ON lf_ops.estados_transiciones USING btree (transition_id);
CREATE UNIQUE INDEX ux_menu_permisos_numeric ON lf_ops.menu_items_permisos USING btree (menu_item_id, permission_id);
CREATE UNIQUE INDEX ux_alert_numeric ON lf_ops.observabilidad_alertas USING btree (alert_id);
CREATE UNIQUE INDEX ux_variant_numeric ON lf_ops.pantalla_variantes USING btree (variant_id);
CREATE UNIQUE INDEX ux_pantallas_perfiles_numeric ON lf_ops.pantallas_perfiles USING btree (pantalla_id, profile_id);
CREATE UNIQUE INDEX ux_pantallas_permisos_numeric ON lf_ops.pantallas_permisos USING btree (pantalla_id, permission_id);
CREATE UNIQUE INDEX ux_approval_number ON lf_ops.aprobaciones_registros USING btree (approval_number);
CREATE INDEX idx_audit_events_load ON lf_ops.auditoria_eventos USING btree (load_id, event_timestamp DESC);
CREATE UNIQUE INDEX ux_audit_number ON lf_ops.auditoria_eventos USING btree (audit_number);
CREATE UNIQUE INDEX ux_file_number ON lf_ops.cargas_archivos USING btree (file_number);
CREATE UNIQUE INDEX ux_load_number ON lf_ops.cargas_lotes USING btree (load_number);

CREATE UNIQUE INDEX ux_icon_catalog_numeric ON lf_design.icon_catalog USING btree (icon_id);
CREATE UNIQUE INDEX ux_visual_decisions_numeric ON lf_design.visual_decisions USING btree (visual_decision_id);

CREATE INDEX idx_lf_strategy_snapshots_payload ON public.lf_strategy_snapshots USING gin (content_payload);
CREATE INDEX idx_lf_strategy_snapshots_metadata ON public.lf_strategy_snapshots USING gin (metadata);
CREATE INDEX ix_lf_backlog_errores_metadata_gin ON public.lf_backlog_errores_operativos USING gin (metadata);
