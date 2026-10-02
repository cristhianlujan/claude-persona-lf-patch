alter table programacion.engineering_plan_units
  add column if not exists source_event_id bigint,
  add column if not exists source_group_code text,
  add column if not exists transformation_action text,
  add column if not exists unit_metadata jsonb not null default '{}'::jsonb;

alter table programacion.engineering_plan_units
  alter column unit_event_id drop not null,
  drop constraint if exists engineering_plan_units_unit_class_check,
  drop constraint if exists engineering_plan_units_lot_code_check,
  drop constraint if exists engineering_plan_units_lot_from_check,
  drop constraint if exists engineering_plan_units_lot_to_check;

alter table programacion.engineering_plan_units
  alter column lot_from type integer using lot_from::integer,
  alter column lot_to type integer using lot_to::integer;

alter table programacion.engineering_plan_units
  add constraint engineering_plan_units_unit_class_generic_ck
    check (length(btrim(unit_class)) between 1 and 80),
  add constraint engineering_plan_units_lot_code_generic_ck
    check (length(btrim(lot_code)) between 1 and 80),
  add constraint engineering_plan_units_lot_from_generic_ck
    check (lot_from >= 0),
  add constraint engineering_plan_units_lot_to_generic_ck
    check (lot_to >= 0),
  add constraint engineering_plan_units_source_event_id_fkey
    foreign key (source_event_id) references public.lf_eventos(id);

update programacion.engineering_plan_units
set source_event_id = coalesce(source_event_id, source_v1_event_id),
    source_group_code = coalesce(source_group_code, v1_macrolote),
    transformation_action = coalesce(transformation_action, remap_action),
    unit_metadata = coalesce(unit_metadata,'{}'::jsonb) || jsonb_build_object(
      'legacy_compat', jsonb_build_object(
        'unit_class', unit_class,
        'v1_macrolote', v1_macrolote,
        'source_v1_event_id', source_v1_event_id,
        'remap_action', remap_action
      )
    );

comment on table programacion.engineering_plan_units is
'Generic engineering plan-unit registry. Canonical fields are plan_code/unit_code/unit_class/lot_code/lot_from/lot_to/source_event_id/source_group_code/transformation_action/unit_metadata. IG v1/v2 fields remain only for backward compatibility.';
comment on column programacion.engineering_plan_units.unit_class is
'Extensible plan-unit classification; not restricted to IG v1/v2 semantics.';
comment on column programacion.engineering_plan_units.unit_event_id is
'Optional unit-specific immutable event. plan_event_id remains the mandatory plan anchor.';
comment on column programacion.engineering_plan_units.source_event_id is
'Generic source/provenance event for this plan unit.';
comment on column programacion.engineering_plan_units.source_group_code is
'Generic source grouping or prior phase/lot code.';
comment on column programacion.engineering_plan_units.transformation_action is
'Generic transformation/remap/reuse action.';
comment on column programacion.engineering_plan_units.unit_metadata is
'Extensible plan-unit metadata; legacy compatibility details may be retained here.';
comment on column programacion.engineering_plan_units.v1_macrolote is
'Legacy IG compatibility column; do not use for new plans. Use source_group_code.';
comment on column programacion.engineering_plan_units.source_v1_event_id is
'Legacy IG compatibility column; do not use for new plans. Use source_event_id.';
comment on column programacion.engineering_plan_units.remap_action is
'Legacy IG compatibility column; do not use for new plans. Use transformation_action.';
