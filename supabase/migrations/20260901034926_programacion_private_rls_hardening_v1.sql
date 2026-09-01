alter table programacion.agentes enable row level security;
alter table programacion.casos_referencia_calidad enable row level security;
alter table programacion.contratos enable row level security;
alter table programacion.herramientas enable row level security;
alter table programacion.input_gap_proposals enable row level security;
alter table programacion.perfiles_calidad enable row level security;
alter table programacion.perfiles_calidad_controles enable row level security;
alter table programacion.vinculos_ekb enable row level security;

create policy programacion_quality_reader_select
on programacion.perfiles_calidad
as permissive
for select
to programacion_builder, programacion_auditor
using (true);

create policy programacion_quality_controls_reader_select
on programacion.perfiles_calidad_controles
as permissive
for select
to programacion_builder, programacion_auditor
using (true);