-- BORRADOR NO DESPLEGABLE (v2). SALY exclusivamente. Ejecutar únicamente en PG17 aislado.
-- v2: el proceso se ubica en un nodo MODULO existente de saly.nucleo_nodos (no se duplica jerarquía).
-- No modifica el núcleo de reglas, sus nodos, ni otros negocios.
CREATE TABLE saly.procesos (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  codigo text NOT NULL UNIQUE CHECK (btrim(codigo) <> ''),
  nodo_codigo text NOT NULL REFERENCES saly.nucleo_nodos(codigo),
  creado_en timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE saly.procesos_versiones (
  proceso_id bigint NOT NULL REFERENCES saly.procesos(id),
  version integer NOT NULL CHECK (version > 0),
  titulo text NOT NULL CHECK (btrim(titulo) <> ''),
  motivo text NOT NULL CHECK (btrim(motivo) <> ''),
  origen_ref text NOT NULL CHECK (btrim(origen_ref) <> ''),
  creado_por text NOT NULL CHECK (btrim(creado_por) <> ''),
  estado text NOT NULL DEFAULT 'BORRADOR' CHECK (estado IN ('BORRADOR','SELLADA')),
  creado_en timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (proceso_id,version)
);
CREATE TABLE saly.procesos_pasos (
  proceso_id bigint NOT NULL REFERENCES saly.procesos(id),
  paso_id bigint GENERATED ALWAYS AS IDENTITY,
  codigo text NOT NULL CHECK (btrim(codigo) <> ''),
  PRIMARY KEY (proceso_id,paso_id), UNIQUE (proceso_id,codigo)
);
CREATE TABLE saly.procesos_pasos_versiones (
  proceso_id bigint NOT NULL,
  paso_id bigint NOT NULL,
  version integer NOT NULL CHECK (version > 0),
  titulo text NOT NULL CHECK (btrim(titulo) <> ''),
  descripcion text NOT NULL CHECK (btrim(descripcion) <> ''),
  PRIMARY KEY (proceso_id,paso_id,version),
  FOREIGN KEY (proceso_id,paso_id) REFERENCES saly.procesos_pasos(proceso_id,paso_id)
);
CREATE TABLE saly.procesos_version_pasos (
  proceso_id bigint NOT NULL,
  proceso_version integer NOT NULL,
  paso_id bigint NOT NULL,
  paso_version integer NOT NULL,
  orden integer NOT NULL CHECK (orden > 0),
  es_inicio boolean NOT NULL DEFAULT false,
  es_fin boolean NOT NULL DEFAULT false,
  PRIMARY KEY (proceso_id,proceso_version,paso_id),
  UNIQUE (proceso_id,proceso_version,orden),
  FOREIGN KEY (proceso_id,proceso_version) REFERENCES saly.procesos_versiones(proceso_id,version),
  FOREIGN KEY (proceso_id,paso_id,paso_version) REFERENCES saly.procesos_pasos_versiones(proceso_id,paso_id,version)
);
CREATE UNIQUE INDEX procesos_un_inicio_idx ON saly.procesos_version_pasos(proceso_id,proceso_version) WHERE es_inicio;
CREATE TABLE saly.procesos_version_transiciones (
  proceso_id bigint NOT NULL,
  proceso_version integer NOT NULL,
  desde_paso bigint NOT NULL,
  hacia_paso bigint NOT NULL,
  ruta text NOT NULL CHECK (btrim(ruta) <> ''),
  PRIMARY KEY (proceso_id,proceso_version,desde_paso,ruta),
  FOREIGN KEY (proceso_id,proceso_version,desde_paso) REFERENCES saly.procesos_version_pasos(proceso_id,proceso_version,paso_id),
  FOREIGN KEY (proceso_id,proceso_version,hacia_paso) REFERENCES saly.procesos_version_pasos(proceso_id,proceso_version,paso_id)
);
-- Identidades y definiciones de pasos son inmutables: para corregir, insertar nueva versión.
CREATE FUNCTION saly.procesos_inmutable_v1() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN RAISE EXCEPTION 'SALY_PROCESO_INMUTABLE' USING ERRCODE='55000'; END; $$;
CREATE TRIGGER procesos_identidad_inmutable BEFORE UPDATE OR DELETE ON saly.procesos FOR EACH ROW EXECUTE FUNCTION saly.procesos_inmutable_v1();
CREATE TRIGGER procesos_paso_identidad_inmutable BEFORE UPDATE OR DELETE ON saly.procesos_pasos FOR EACH ROW EXECUTE FUNCTION saly.procesos_inmutable_v1();
CREATE TRIGGER procesos_paso_version_inmutable BEFORE UPDATE OR DELETE ON saly.procesos_pasos_versiones FOR EACH ROW EXECUTE FUNCTION saly.procesos_inmutable_v1();
-- El proceso solo puede ubicarse en un nodo de nivel MODULO del núcleo (la identidad es inmutable tras insertar).
CREATE FUNCTION saly.procesos_nodo_guard_v1() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM saly.nucleo_nodos WHERE codigo=NEW.nodo_codigo AND nivel='MODULO') THEN
    RAISE EXCEPTION 'SALY_PROCESO_NODO_NO_MODULO' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END; $$;
CREATE TRIGGER procesos_nodo_guard BEFORE INSERT ON saly.procesos FOR EACH ROW EXECUTE FUNCTION saly.procesos_nodo_guard_v1();
-- Serializa cambios de composición contra sellado y bloquea traslado entre versiones.
CREATE FUNCTION saly.procesos_composicion_guard_v1() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE p bigint; v integer; e text;
BEGIN
  IF TG_OP='UPDATE' AND (NEW.proceso_id,NEW.proceso_version) IS DISTINCT FROM (OLD.proceso_id,OLD.proceso_version) THEN
    RAISE EXCEPTION 'SALY_PROCESO_TRASLADO_PROHIBIDO' USING ERRCODE='55000';
  END IF;
  IF TG_OP='DELETE' THEN p:=OLD.proceso_id; v:=OLD.proceso_version; ELSE p:=NEW.proceso_id; v:=NEW.proceso_version; END IF;
  SELECT estado INTO e FROM saly.procesos_versiones WHERE proceso_id=p AND version=v FOR UPDATE;
  IF e IS DISTINCT FROM 'BORRADOR' THEN RAISE EXCEPTION 'SALY_PROCESO_NO_EDITABLE' USING ERRCODE='55000'; END IF;
  IF TG_OP='DELETE' THEN RETURN OLD; END IF; RETURN NEW;
END; $$;
CREATE TRIGGER procesos_composicion_guard BEFORE INSERT OR UPDATE OR DELETE ON saly.procesos_version_pasos FOR EACH ROW EXECUTE FUNCTION saly.procesos_composicion_guard_v1();
CREATE TRIGGER procesos_transicion_guard BEFORE INSERT OR UPDATE OR DELETE ON saly.procesos_version_transiciones FOR EACH ROW EXECUTE FUNCTION saly.procesos_composicion_guard_v1();
-- Sellado de definición, NO publicación, aprobación, ni activación operacional.
CREATE FUNCTION saly.procesos_version_guard_v1() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE total integer; alcanzables integer; con_salida integer;
BEGIN
  IF TG_OP='INSERT' THEN
    IF NEW.estado <> 'BORRADOR' THEN RAISE EXCEPTION 'SALY_PROCESO_INSERTAR_BORRADOR' USING ERRCODE='55000'; END IF;
    RETURN NEW;
  END IF;
  IF OLD.estado='SELLADA' OR TG_OP='DELETE' THEN RAISE EXCEPTION 'SALY_PROCESO_VERSION_INMUTABLE' USING ERRCODE='55000'; END IF;
  IF (NEW.proceso_id,NEW.version) IS DISTINCT FROM (OLD.proceso_id,OLD.version) THEN RAISE EXCEPTION 'SALY_PROCESO_IDENTIDAD_INMUTABLE' USING ERRCODE='55000'; END IF;
  IF NEW.estado='SELLADA' THEN
    SELECT count(*) INTO total FROM saly.procesos_version_pasos WHERE proceso_id=NEW.proceso_id AND proceso_version=NEW.version;
    IF NOT EXISTS (SELECT 1 FROM saly.procesos_version_pasos WHERE proceso_id=NEW.proceso_id AND proceso_version=NEW.version AND es_inicio)
    OR NOT EXISTS (SELECT 1 FROM saly.procesos_version_pasos WHERE proceso_id=NEW.proceso_id AND proceso_version=NEW.version AND es_fin) THEN
      RAISE EXCEPTION 'SALY_PROCESO_SIN_INICIO_FIN' USING ERRCODE='23514';
    END IF;
    WITH RECURSIVE r(paso) AS (
      SELECT paso_id FROM saly.procesos_version_pasos WHERE proceso_id=NEW.proceso_id AND proceso_version=NEW.version AND es_inicio
      UNION SELECT t.hacia_paso FROM r JOIN saly.procesos_version_transiciones t ON t.desde_paso=r.paso WHERE t.proceso_id=NEW.proceso_id AND t.proceso_version=NEW.version
    ) SELECT count(*) INTO alcanzables FROM r;
    WITH RECURSIVE r(paso) AS (
      SELECT paso_id FROM saly.procesos_version_pasos WHERE proceso_id=NEW.proceso_id AND proceso_version=NEW.version AND es_fin
      UNION SELECT t.desde_paso FROM r JOIN saly.procesos_version_transiciones t ON t.hacia_paso=r.paso WHERE t.proceso_id=NEW.proceso_id AND t.proceso_version=NEW.version
    ) SELECT count(*) INTO con_salida FROM r;
    IF total<>alcanzables OR total<>con_salida THEN RAISE EXCEPTION 'SALY_PROCESO_FLUJO_INCOMPLETO' USING ERRCODE='23514'; END IF;
    IF EXISTS (SELECT 1 FROM saly.procesos_version_transiciones t JOIN saly.procesos_version_pasos p ON (p.proceso_id,p.proceso_version,p.paso_id)=(t.proceso_id,t.proceso_version,t.desde_paso) WHERE t.proceso_id=NEW.proceso_id AND t.proceso_version=NEW.version AND p.es_fin) THEN RAISE EXCEPTION 'SALY_PROCESO_FIN_CON_SALIDA' USING ERRCODE='23514'; END IF;
  END IF;
  RETURN NEW;
END; $$;
CREATE TRIGGER procesos_version_guard BEFORE INSERT OR UPDATE OR DELETE ON saly.procesos_versiones FOR EACH ROW EXECUTE FUNCTION saly.procesos_version_guard_v1();
-- Cerrado por defecto: sin grants de escritura para clientes; no conceder nuevas puertas aquí.
DO $$ DECLARE t text; BEGIN
  FOREACH t IN ARRAY ARRAY['procesos','procesos_versiones','procesos_pasos','procesos_pasos_versiones','procesos_version_pasos','procesos_version_transiciones'] LOOP
    EXECUTE format('ALTER TABLE saly.%I ENABLE ROW LEVEL SECURITY',t);
    EXECUTE format('REVOKE ALL ON TABLE saly.%I FROM PUBLIC, anon, authenticated, service_role',t);
  END LOOP;
END $$;
REVOKE ALL ON FUNCTION saly.procesos_inmutable_v1(), saly.procesos_composicion_guard_v1(), saly.procesos_version_guard_v1(), saly.procesos_nodo_guard_v1() FROM PUBLIC, anon, authenticated, service_role;
