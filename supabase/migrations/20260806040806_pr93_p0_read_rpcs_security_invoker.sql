-- PR93 · Production readiness P0
-- Remove unnecessary owner-privilege execution from public read-only RPCs.

begin;

alter function public.lf_buscar_activos(text, text, text, text, integer)
  security invoker;

alter function public.lf_healthcheck()
  security invoker;

commit;
