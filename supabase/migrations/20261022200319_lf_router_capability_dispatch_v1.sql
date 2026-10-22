-- Generic Router dispatch: capabilities are DATA (lf_router_capability_v1), not code. Adding a capability
-- = inserting a row + a handler lf_cap_*(text,jsonb). The dispatcher never changes again.
-- Uniform receiver contract: decision PERMITIDO | DENEGADO | FALTA_INFO with plain-language reason,
-- reason_code, steps and next step. Additive only: lf_router_resolve_v1 is NOT modified.
-- Applied only through ACTUALIZACION_DB_LF / LF Migration Merge Train.
BEGIN;

CREATE TABLE IF NOT EXISTS public.lf_router_capability_v1 (
  capability_code text PRIMARY KEY,
  descripcion_es  text NOT NULL,
  intent_terms    text[] NOT NULL,
  handler_fn      text,
  effect          text NOT NULL CHECK (effect IN ('READ_ONLY','PROPOSE_ONLY')),
  status          text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','DISABLED')),
  disabled_reason text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT lf_router_capability_handler_ck CHECK (
    (status='ACTIVE' AND handler_fn ~ '^lf_cap_[a-z0-9_]+$')
    OR (status='DISABLED' AND disabled_reason IS NOT NULL))
);
ALTER TABLE public.lf_router_capability_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.lf_router_capability_v1 FROM PUBLIC;

DO $g$
DECLARE v_role text;
BEGIN
  FOREACH v_role IN ARRAY ARRAY['anon','authenticated'] LOOP
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname=v_role) THEN
      EXECUTE format('REVOKE ALL ON TABLE public.lf_router_capability_v1 FROM %I',v_role); END IF;
  END LOOP;
  FOREACH v_role IN ARRAY ARRAY['service_role','supabase_read_only_user'] LOOP
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname=v_role) THEN
      EXECUTE format('GRANT SELECT ON TABLE public.lf_router_capability_v1 TO %I',v_role);
      IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='lf_router_capability_v1' AND policyname='lf_router_capability_read_'||v_role) THEN
        EXECUTE format('CREATE POLICY %I ON public.lf_router_capability_v1 FOR SELECT TO %I USING (true)','lf_router_capability_read_'||v_role,v_role);
      END IF;
    END IF;
  END LOOP;
END
$g$;

-- ---------------------------------------------------------------- handlers (uniform contract)
CREATE OR REPLACE FUNCTION public.lf_cap_estado_en_curso_v1(p_request_text text, p_caller jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SET search_path TO 'pg_catalog','public' AS $f$
DECLARE v jsonb; v_np int; v_ne int; v_stale int; v_router text;
BEGIN
  v := public.lf_estado_en_curso_v1();
  v_np := jsonb_array_length(v->'planes_en_curso');
  v_ne := jsonb_array_length(v->'estrategias_en_ejecucion');
  SELECT count(*) INTO v_stale FROM jsonb_array_elements(v->'estrategias_en_ejecucion') x WHERE (x->>'sin_movimiento')::boolean;
  SELECT string_agg(x->>'work_code'||' '||(x->>'estado')||' '||coalesce(x->>'avance_pct','?')||'% ('||(x->>'checkpoints')||')',' · ')
    INTO v_router FROM jsonb_array_elements(v->'plan_router') x;
  RETURN jsonb_build_object(
    'decision','PERMITIDO',
    'reason_code','READ_ONLY_OPEN',
    'motivo_es','Es una consulta de solo lectura: no cambia nada y no requiere permiso de escritura.',
    'respuesta_es', format('Hay %s planes en curso y %s estrategias en ejecución (%s sin movimiento en más de %s días). Plan del Router: %s.',
        v_np, v_ne, v_stale, v->>'stale_after_days', coalesce(v_router,'sin registro')),
    'siguiente_paso_es', CASE WHEN v_stale>0 THEN 'Decidir cuáles de las estrategias sin movimiento se cierran; esa decisión es del propietario.' ELSE 'Nada pendiente.' END,
    'pasos', '[]'::jsonb,
    'read_only', true,
    'datos', v);
END
$f$;

CREATE OR REPLACE FUNCTION public.lf_cap_regla_create_v1(p_request_text text, p_caller jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SET search_path TO 'pg_catalog','public' AS $f$
DECLARE
  v_pre jsonb := public.lf_regla_create_preflight_v1(p_request_text);
  v_actor text := nullif(btrim(coalesce(p_caller->>'actor','')),'');
  v_exec  text := nullif(btrim(coalesce(p_caller->>'execution_id','')),'');
  v_open boolean := false;
  v_datos jsonb := coalesce(p_caller->'datos','{}'::jsonb);
  v_missing jsonb;
  v_ident_ok boolean;
  v_perm jsonb;
  v_pregunta text;
  v_resp text;
BEGIN
  IF v_exec IS NOT NULL THEN
    SELECT true INTO v_open FROM public.lf_operation_execution e
     WHERE e.execution_id=v_exec AND e.operation_code='CREACION_REGLA_LF' AND e.status IN ('IN_PROGRESS','RUNNING');
    v_open := coalesce(v_open,false);
  END IF;
  v_ident_ok := (v_actor IS NOT NULL AND v_open);
  SELECT coalesce(jsonb_agg(r),'[]'::jsonb) INTO v_missing
    FROM jsonb_array_elements_text(v_pre->'required_inputs_governed') r
   WHERE nullif(btrim(coalesce(v_datos->>r,'')),'') IS NULL;

  v_perm := jsonb_build_array(
    jsonb_build_object('accion','EXPLICAR_Y_PROPONER','decision','PERMITIDO','reason_code','PROPOSE_ONLY_OPEN',
      'motivo_es','Puedo explicarte qué se necesita y proponerte los pasos; esto no escribe nada.'),
    jsonb_build_object('accion','GUARDAR_EN_EXPLORACION',
      'decision', CASE WHEN v_ident_ok THEN 'PERMITIDO' ELSE 'DENEGADO' END,
      'reason_code', CASE WHEN v_ident_ok THEN 'OK' ELSE 'CALLER_IDENTITY_AND_OPEN_EXECUTION_REQUIRED' END,
      'motivo_es', CASE WHEN v_ident_ok THEN 'Hay quien solicita y una ejecución abierta de CREACION_REGLA_LF; se acepta información parcial.'
        ELSE 'No puedo guardar todavía: falta identificar quién solicita (actor) y una ejecución abierta de CREACION_REGLA_LF (execution_id).' END,
      'siguiente_paso_es', CASE WHEN v_ident_ok THEN 'Enviar los datos que tengas; se guardan en el almacén de exploración.'
        ELSE 'La capa que llama debe abrir una ejecución de CREACION_REGLA_LF y enviar actor y execution_id.' END),
    jsonb_build_object('accion','GUARDAR_CANDIDATA_GOBERNADA',
      'decision', CASE WHEN v_ident_ok AND jsonb_array_length(v_missing)=0 THEN 'PERMITIDO' ELSE 'DENEGADO' END,
      'reason_code', CASE WHEN NOT v_ident_ok THEN 'CALLER_IDENTITY_AND_OPEN_EXECUTION_REQUIRED'
                          WHEN jsonb_array_length(v_missing)>0 THEN 'INCOMPLETE_INPUT_FOR_GOVERNED' ELSE 'OK' END,
      'motivo_es', CASE WHEN NOT v_ident_ok THEN 'Sin actor y sin ejecución abierta no se puede guardar como candidata gobernada.'
                        WHEN jsonb_array_length(v_missing)>0 THEN 'El modo gobernado exige información completa; faltan: '||(SELECT string_agg(x,', ') FROM jsonb_array_elements_text(v_missing) x)||'.'
                        ELSE 'Información completa y ejecución abierta: se guarda como CANDIDATA.' END,
      'faltan', v_missing,
      'siguiente_paso_es', CASE WHEN NOT v_ident_ok THEN 'Abrir la ejecución y enviar actor + execution_id.'
                                WHEN jsonb_array_length(v_missing)>0 THEN 'Completar los campos faltantes.' ELSE 'Guardar.' END),
    jsonb_build_object('accion','PROMOVER_A_VIGENTE','decision','DENEGADO','reason_code','PROMOTION_NOT_PART_OF_THIS_OPERATION',
      'motivo_es','Esta operación solo crea candidatas; nunca publica una regla como VIGENTE.',
      'siguiente_paso_es','La promoción es otro proceso con su propia decisión del propietario.'));

  v_pregunta := CASE WHEN nullif(btrim(coalesce(v_datos->>'descripcion','')),'') IS NULL
    THEN format('¿Qué condición exacta debe validar la regla? (tu pedido: "%s")', left(p_request_text,120)) END;

  v_resp := 'Puedo ayudarte a crear la regla como CANDIDATA (nunca vigente). '
    || CASE WHEN v_ident_ok THEN 'Hay actor y ejecución abierta, así que puedo guardarla.'
            ELSE 'Guardarla ahora está DENEGADO: falta identificar quién solicita y una ejecución abierta de CREACION_REGLA_LF (CALLER_IDENTITY_AND_OPEN_EXECUTION_REQUIRED).' END
    || CASE WHEN jsonb_array_length(v_missing)>0 THEN ' Para el modo gobernado faltan: '||(SELECT string_agg(x,', ') FROM jsonb_array_elements_text(v_missing) x)||'.' ELSE '' END
    || ' Promoverla a VIGENTE no forma parte de esta operación.';

  RETURN jsonb_build_object(
    'decision','PERMITIDO','reason_code','PROPOSE_ONLY_OPEN',
    'motivo_es','Puedo guiarte; escribir depende de permisos que se detallan abajo.',
    'respuesta_es', v_resp,
    'permisos', v_perm,
    'faltan', v_missing,
    'pregunta', v_pregunta,
    'pasos', jsonb_build_array(
      '1. Abrir una ejecución de CREACION_REGLA_LF (la capa que llama aporta actor y execution_id).',
      '2. Elegir modo: EXPLORACION (información parcial) o GOBERNADO (codigo, categoria, titulo, descripcion).',
      '3. Guardar como CANDIDATA.',
      '4. La promoción a VIGENTE es un proceso aparte y decide el propietario.'),
    'siguiente_paso_es', CASE WHEN NOT v_ident_ok THEN 'Abrir la ejecución y enviar actor + execution_id.' ELSE 'Enviar los datos de la regla.' END,
    'caller_verificacion','DECLARADO_POR_CAPA_LLAMADORA_NO_VERIFICADO_CRIPTOGRAFICAMENTE',
    'read_only', true,
    'datos', v_pre);
END
$f$;

-- ---------------------------------------------------------------- generic dispatcher
CREATE OR REPLACE FUNCTION public.lf_router_dispatch_v1(
  p_request_text text, p_capability_hint text DEFAULT NULL, p_caller jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SET search_path TO 'pg_catalog','public' AS $f$
DECLARE
  v_norm text := translate(lower(coalesce(p_request_text,'')),'áéíóúüñ','aeiouun');
  v_cap public.lf_router_capability_v1%ROWTYPE;
  v_best int; v_second int; v_n_best int; v_res jsonb; v_resolve jsonb; v_fn regprocedure;
  v_opts jsonb;
BEGIN
  IF p_capability_hint IS NOT NULL THEN
    SELECT * INTO v_cap FROM public.lf_router_capability_v1 WHERE capability_code=p_capability_hint;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('schema_version','LF_ROUTER_DISPATCH_V1','router','ACT-0001','decision','FALTA_INFO',
        'reason_code','CAPABILITY_UNKNOWN','motivo_es','La capacidad indicada no existe en el catálogo.',
        'pregunta','¿Cuál de las capacidades registradas quieres usar?',
        'opciones',(SELECT coalesce(jsonb_agg(capability_code ORDER BY capability_code),'[]'::jsonb) FROM public.lf_router_capability_v1));
    END IF;
  ELSE
    WITH s AS (
      SELECT c.capability_code,
             coalesce((SELECT sum(length(t)) FROM unnest(c.intent_terms) t WHERE position(t in v_norm)>0),0)::int AS score
        FROM public.lf_router_capability_v1 c)
    SELECT max(score), count(*) FILTER (WHERE score=(SELECT max(score) FROM s)),
           coalesce((SELECT max(score) FROM s WHERE score<(SELECT max(score) FROM s)),0)
      INTO v_best, v_n_best, v_second FROM s;
    IF coalesce(v_best,0)=0 THEN
      BEGIN v_resolve := public.lf_router_resolve_v1(p_request_text);
      EXCEPTION WHEN OTHERS THEN v_resolve := NULL; END;
      RETURN jsonb_build_object('schema_version','LF_ROUTER_DISPATCH_V1','router','ACT-0001','decision','FALTA_INFO',
        'reason_code','NO_CAPABILITY_MATCH',
        'motivo_es','No encontré una capacidad registrada que corresponda a tu pedido.',
        'respuesta_es','No sé todavía a qué capacidad corresponde. Lo paso a la capa semántica con lo que el Router entendió.',
        'pregunta','¿Qué quieres lograr: consultar un estado, crear/cambiar un activo o algo distinto?',
        'opciones',(SELECT coalesce(jsonb_agg(jsonb_build_object('capacidad',capability_code,'descripcion',descripcion_es) ORDER BY capability_code),'[]'::jsonb) FROM public.lf_router_capability_v1),
        'resolve_handoff', v_resolve, 'downstream_execution_allowed', false);
    ELSIF v_n_best>1 OR v_second>0 THEN
      SELECT jsonb_agg(jsonb_build_object('capacidad',capability_code,'descripcion',descripcion_es)) INTO v_opts
        FROM public.lf_router_capability_v1 c
       WHERE coalesce((SELECT sum(length(t)) FROM unnest(c.intent_terms) t WHERE position(t in v_norm)>0),0)>0;
      RETURN jsonb_build_object('schema_version','LF_ROUTER_DISPATCH_V1','router','ACT-0001','decision','FALTA_INFO',
        'reason_code','AMBIGUOUS_CAPABILITY','motivo_es','Tu pedido encaja con más de una capacidad.',
        'pregunta','¿Cuál de estas quieres?','opciones',v_opts,'downstream_execution_allowed',false);
    END IF;
    SELECT c.* INTO v_cap FROM public.lf_router_capability_v1 c
     WHERE coalesce((SELECT sum(length(t)) FROM unnest(c.intent_terms) t WHERE position(t in v_norm)>0),0)=v_best;
  END IF;

  IF v_cap.status='DISABLED' THEN
    RETURN jsonb_build_object('schema_version','LF_ROUTER_DISPATCH_V1','router','ACT-0001','decision','DENEGADO',
      'capability',v_cap.capability_code,'reason_code','CAPABILITY_DISABLED',
      'motivo_es',v_cap.disabled_reason,
      'respuesta_es','DENEGADO: '||v_cap.disabled_reason,
      'siguiente_paso_es','Pedir al propietario que habilite la capacidad (cambiar su estado a ACTIVE con su handler).',
      'downstream_execution_allowed',false);
  END IF;

  v_fn := to_regprocedure(format('public.%I(text,jsonb)',v_cap.handler_fn));
  IF v_fn IS NULL THEN
    RETURN jsonb_build_object('schema_version','LF_ROUTER_DISPATCH_V1','router','ACT-0001','decision','DENEGADO',
      'capability',v_cap.capability_code,'reason_code','HANDLER_NOT_FOUND',
      'motivo_es','La capacidad está registrada pero su función receptora no existe.',
      'siguiente_paso_es','Corregir el catálogo o crear la función '||v_cap.handler_fn||'(text,jsonb).','downstream_execution_allowed',false);
  END IF;

  EXECUTE format('SELECT public.%I($1,$2)',v_cap.handler_fn) INTO v_res USING p_request_text, coalesce(p_caller,'{}'::jsonb);
  RETURN jsonb_build_object('schema_version','LF_ROUTER_DISPATCH_V1','router','ACT-0001',
    'capability',v_cap.capability_code,'receiver',v_cap.handler_fn,'effect',v_cap.effect,
    'decision',v_res->>'decision','respuesta_es',v_res->>'respuesta_es','resultado',v_res,
    'downstream_execution_allowed',false);
END
$f$;

DO $g$
DECLARE v_fn text; v_role text;
BEGIN
  FOREACH v_fn IN ARRAY ARRAY['lf_cap_estado_en_curso_v1(text,jsonb)','lf_cap_regla_create_v1(text,jsonb)','lf_router_dispatch_v1(text,text,jsonb)'] LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION public.%s FROM PUBLIC',v_fn);
    FOREACH v_role IN ARRAY ARRAY['anon','authenticated'] LOOP
      IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname=v_role) THEN
        EXECUTE format('REVOKE ALL ON FUNCTION public.%s FROM %I',v_fn,v_role); END IF;
    END LOOP;
    FOREACH v_role IN ARRAY ARRAY['service_role','supabase_read_only_user'] LOOP
      IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname=v_role) THEN
        EXECUTE format('GRANT EXECUTE ON FUNCTION public.%s TO %I',v_fn,v_role); END IF;
    END LOOP;
  END LOOP;
END
$g$;

-- ---------------------------------------------------------------- seed capabilities (data, idempotent)
INSERT INTO public.lf_router_capability_v1 (capability_code,descripcion_es,intent_terms,handler_fn,effect,status,disabled_reason) VALUES
 ('ESTADO_EN_CURSO','Estado real de planes y estrategias en curso, incluido el plan del Router (solo lectura).',
  ARRAY['en curso','corriendo','en ejecucion','que estrategias','estrategias estan','estrategias activas','que planes','planes estan','plan del router','estado de los planes','estado del router'],
  'lf_cap_estado_en_curso_v1','READ_ONLY','ACTIVE',NULL),
 ('REGLA_CREAR','Crear una regla nueva como CANDIDATA: qué se necesita, permisos y pasos (no promueve a vigente).',
  ARRAY['crear una regla','crear regla','nueva regla','regla nueva','crear la regla','agregar una regla'],
  'lf_cap_regla_create_v1','PROPOSE_ONLY','ACTIVE',NULL),
 ('PERFIL_PRODUCTO_ASESOR','Respuesta de producto del perfil PERFIL-PRODUCT-DIRECTOR-LF.',
  ARRAY['perfil de producto','perfil producto','director de producto','product director','asesor de producto'],
  NULL,'PROPOSE_ONLY','DISABLED','El perfil PERFIL-PRODUCT-DIRECTOR-LF está NO_HABILITADO en runtime; solo el propietario puede habilitarlo.')
ON CONFLICT (capability_code) DO NOTHING;

-- ---------------------------------------------------------------- in-transaction rehearsal (aborts on failure)
DO $t$
DECLARE r jsonb;
BEGIN
  r := public.lf_router_dispatch_v1('Quiero crear una regla nueva para validar montos');
  IF r->>'capability' IS DISTINCT FROM 'REGLA_CREAR' OR r->>'decision' IS DISTINCT FROM 'PERMITIDO' THEN RAISE EXCEPTION 'REHEARSAL regla: %', r; END IF;
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'resultado'->'permisos') p
      WHERE p->>'accion'='GUARDAR_CANDIDATA_GOBERNADA' AND p->>'decision'='DENEGADO' AND p->>'reason_code'='CALLER_IDENTITY_AND_OPEN_EXECUTION_REQUIRED')
     THEN RAISE EXCEPTION 'REHEARSAL regla denial: %', r; END IF;
  IF r->'resultado'->>'pregunta' IS NULL OR r->>'respuesta_es' IS NULL THEN RAISE EXCEPTION 'REHEARSAL regla pregunta: %', r; END IF;
  r := public.lf_router_dispatch_v1('¿Qué estrategias están corriendo?');
  IF r->>'capability' IS DISTINCT FROM 'ESTADO_EN_CURSO' OR r->>'decision' IS DISTINCT FROM 'PERMITIDO'
     OR (r->'resultado'->>'read_only')::boolean IS NOT TRUE THEN RAISE EXCEPTION 'REHEARSAL estado: %', r; END IF;
  r := public.lf_router_dispatch_v1('quiero usar el perfil de producto');
  IF r->>'decision' IS DISTINCT FROM 'DENEGADO' OR r->>'reason_code' IS DISTINCT FROM 'CAPABILITY_DISABLED' THEN RAISE EXCEPTION 'REHEARSAL perfil: %', r; END IF;
  r := public.lf_router_dispatch_v1('hola, cómo estás');
  IF r->>'decision' IS DISTINCT FROM 'FALTA_INFO' OR r->>'pregunta' IS NULL THEN RAISE EXCEPTION 'REHEARSAL sin match: %', r; END IF;
  r := public.lf_router_dispatch_v1('crear regla y plan del router');
  IF r->>'reason_code' IS DISTINCT FROM 'AMBIGUOUS_CAPABILITY' OR jsonb_array_length(r->'opciones')<>2 THEN RAISE EXCEPTION 'REHEARSAL ambiguo: %', r; END IF;
  r := public.lf_router_dispatch_v1('lo que sea','NO_EXISTE');
  IF r->>'reason_code' IS DISTINCT FROM 'CAPABILITY_UNKNOWN' THEN RAISE EXCEPTION 'REHEARSAL hint: %', r; END IF;
END
$t$;

COMMIT;
