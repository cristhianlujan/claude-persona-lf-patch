-- DP-IG-03: extensión aditiva de diagnóstico de la única puerta canónica.
-- No reemplaza firma de nodo/fecha, no activa consumidores ni modifica controles IG.
BEGIN;
DO $pre$
BEGIN
 IF to_regprocedure('lf_ops.nucleo_reglas_efectivas_v1(integer,text,text)') IS NOT NULL
 THEN RAISE EXCEPTION 'DP_IG_03_SOBRECARGA_EXISTENTE'; END IF;
 IF md5(pg_get_functiondef('lf_ops.nucleo_reglas_efectivas_v1(text,timestamptz)'::regprocedure))
    IS DISTINCT FROM '6a7f47636bb1150d650d61214d93152b'
    OR to_regclass('lf_ops.v_reglas_compat_v1') IS NULL
    OR to_regprocedure('programacion.fn_input_effective_rule_links_v1(integer,text)') IS NULL
 THEN RAISE EXCEPTION 'DP_IG_03_PREIMAGEN_DISTINTA'; END IF;
END $pre$;

CREATE FUNCTION lf_ops.nucleo_reglas_efectivas_v1(
 p_pantalla_id integer, p_consumer text, p_proyeccion text
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER
SET search_path = pg_catalog, lf_ops
AS $dpig03$
DECLARE
 v_nodo text;
 v_nativas jsonb := '[]'::jsonb;
 v_respaldo jsonb := '[]'::jsonb;
 v_reglas jsonb;
 v_estado text;
 v_fuente text;
 v_num_links bigint;
 v_num_rows bigint;
 v_no_resueltas bigint;
 v_desconfianza boolean := false;
 v_fecha timestamptz := now();
BEGIN
 IF p_pantalla_id IS NULL OR NOT EXISTS (SELECT 1 FROM lf_ops.pantallas WHERE id=p_pantalla_id) THEN
   RAISE EXCEPTION 'DP_IG_03_PANTALLA_INEXISTENTE: %', p_pantalla_id USING ERRCODE='22023';
 END IF;
 IF p_consumer IS NULL OR btrim(p_consumer)='' THEN
   RAISE EXCEPTION 'DP_IG_03_CONSUMER_INVALIDO' USING ERRCODE='22023';
 END IF;
 IF p_proyeccion IS NULL OR p_proyeccion NOT IN ('DIRECTAS','IG_EFECTIVAS','CONTRATO_PANTALLA') THEN
   RAISE EXCEPTION 'DP_IG_03_PROYECCION_INVALIDA: %', p_proyeccion USING ERRCODE='22023';
 END IF;
 SELECT n.codigo INTO v_nodo FROM lf_ops.nucleo_nodos n WHERE n.pantalla_id=p_pantalla_id;
 IF v_nodo IS NOT NULL THEN
   SELECT coalesce(jsonb_agg(jsonb_build_object(
       'resolucion',to_jsonb(e),'version',to_jsonb(v),'familia',r.familia,
       'naturaleza',r.naturaleza,'regla_legacy_id',r.regla_legacy_id)
       ORDER BY e.regla,e.version,e.nodo_origen),'[]'::jsonb),
     coalesce(bool_or(v.estado IS DISTINCT FROM 'PUBLICADA' OR r.estado IS DISTINCT FROM 'VIGENTE'
                     OR e.conflicto IS NOT NULL),false)
   INTO v_nativas,v_desconfianza
   FROM lf_ops.nucleo_reglas_efectivas_v1(v_nodo,v_fecha) e
   LEFT JOIN lf_ops.nucleo_regla_versiones v ON v.regla=e.regla AND v.version=e.version
   LEFT JOIN lf_ops.nucleo_reglas r ON r.codigo=e.regla;
 END IF;
 -- La proyección antigua del contrato requiere cadena pantalla->módulo->shell.
 -- No fabricar un conjunto vacío cuando el contrato anterior no existe.
 IF p_proyeccion='CONTRATO_PANTALLA' AND NOT EXISTS (
   SELECT 1 FROM lf_ops.pantallas p JOIN lf_ops.modulos m ON m.module_id=p.module_id
     JOIN lf_ops.app_shells a ON a.app_shell_id=m.app_shell_id
   WHERE p.id=p_pantalla_id
 ) THEN
   RETURN jsonb_build_object('schema_version','LF_NUCLEO_LECTURA_TRANSICION_V1',
     'estado','SIN_CONTRATO_LEGADO','fuente',null,'diagnostico',true,'pantalla_id',p_pantalla_id,
     'nodo',v_nodo,'fecha',v_fecha,'proyeccion',p_proyeccion,'consumer',p_consumer,
     'reglas',null,'nativas',v_nativas,'respaldo',null);
 END IF;

 -- Adaptador temporal: conservar exactamente la selección legada de vínculos,
 -- sin copiar sus umbrales ni reimplementar su lógica IG. Contenido de las
 -- reglas solo por v_reglas_compat_v1; ningún lector directo nuevo a la tabla.
 WITH links AS MATERIALIZED (
   SELECT rp.regla_id::bigint AS regla_id,'DIRECTA'::text AS binding_source
   FROM lf_ops.reglas_pantallas rp
   WHERE rp.pantalla_id=p_pantalla_id AND p_proyeccion IN ('DIRECTAS','CONTRATO_PANTALLA')
   UNION ALL
   SELECT l.regla_id::bigint,l.binding_source
   FROM programacion.fn_input_effective_rule_links_v1(p_pantalla_id,
          CASE WHEN p_proyeccion='CONTRATO_PANTALLA' THEN 'INPUT_GOVERNANCE' ELSE p_consumer END) l
   WHERE p_proyeccion='IG_EFECTIVAS'
      OR (p_proyeccion='CONTRATO_PANTALLA' AND l.binding_source='DERIVED_GLOBAL')
 ), projected AS (
   SELECT l.regla_id,l.binding_source,r.id,r.codigo,r.categoria,
      CASE p_proyeccion
       WHEN 'DIRECTAS' THEN to_jsonb(r)
       WHEN 'IG_EFECTIVAS' THEN jsonb_build_object('binding_source',l.binding_source,'regla',to_jsonb(r))
       ELSE jsonb_build_object('rule_id',r.id,'rule_code',r.codigo,'category',r.categoria,
         'title',r.titulo,'description',r.descripcion,'reason',r.razon,'config',r.valor_config,
         'transversal',r.es_transversal,'status',r.estado,'origin',r.origen,
         'pending_decision',r.pendiente_decision,'pending_detail',r.pendiente_detalle)
      END AS payload
   FROM links l LEFT JOIN lf_ops.v_reglas_compat_v1 r ON r.id=l.regla_id
 )
 SELECT (SELECT count(*) FROM links),count(*),count(*) FILTER(WHERE id IS NULL),
        coalesce(jsonb_agg(payload ORDER BY CASE WHEN p_proyeccion='DIRECTAS' THEN categoria ELSE '' END,
                    codigo,binding_source,regla_id),'[]'::jsonb)
 INTO v_num_links,v_num_rows,v_no_resueltas,v_respaldo FROM projected;
 IF v_num_rows<>v_num_links OR v_no_resueltas<>0 THEN
   RAISE EXCEPTION 'DP_IG_03_RESPALDO_NO_RESUELTO: pantalla %, links %, filas %, no resueltas %',
    p_pantalla_id,v_num_links,v_num_rows,v_no_resueltas;
 END IF;

 IF v_desconfianza THEN
   v_estado:='NUCLEO_CONFLICTO_NO_CERTIFICADO'; v_fuente:=NULL; v_reglas:=NULL;
 ELSIF jsonb_array_length(v_nativas)>0 AND v_num_links>0 THEN
   -- No hay una equivalencia futura probada ni una política de identidad/solape
   -- entre versiones publicadas y legado. Las dos fuentes permanecen visibles;
   -- no componer una lista efectiva ficticia, ni retirar fallback por un match.
   v_estado:='PARIDAD_MIXTA_PENDIENTE'; v_fuente:=NULL; v_reglas:=NULL;
 ELSIF jsonb_array_length(v_nativas)>0 THEN
   v_estado:='NUCLEO_DISPONIBLE'; v_fuente:='NUCLEO'; v_reglas:=v_nativas;
 ELSE
   v_estado:=CASE WHEN v_nodo IS NULL THEN 'RESPALDO_SIN_NODO' ELSE 'RESPALDO_COMPAT' END;
   v_fuente:='COMPAT'; v_reglas:=v_respaldo;
 END IF;
 RETURN jsonb_build_object('schema_version','LF_NUCLEO_LECTURA_TRANSICION_V1',
   'estado',v_estado,'fuente',v_fuente,'diagnostico',true,'pantalla_id',p_pantalla_id,
   'nodo',v_nodo,'fecha',v_fecha,'proyeccion',p_proyeccion,'consumer',p_consumer,
   'reglas',v_reglas,'nativas',v_nativas,'respaldo',v_respaldo);
END $dpig03$;
-- Solo diagnóstico: ejecutar con los permisos existentes del invocador.
-- No conceder una nueva vía de acceso a consumidores runtime antes del siguiente criterio.
REVOKE ALL ON FUNCTION lf_ops.nucleo_reglas_efectivas_v1(integer,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION lf_ops.nucleo_reglas_efectivas_v1(integer,text,text) TO supabase_read_only_user;
COMMENT ON FUNCTION lf_ops.nucleo_reglas_efectivas_v1(integer,text,text) IS
 'DP-IG-03, contrato transitorio de lectura actual por pantalla. Núcleo original por nodo/fecha preservado. Respaldo compatible por proyección y procedencia explícita; mixto sin resolver queda diagnóstico. No es autorización de efecto, cutover ni prueba de igualdad futura.';
COMMIT;
