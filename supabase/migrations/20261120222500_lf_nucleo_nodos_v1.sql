-- Núcleo de reglas, fase F0: árbol de alcance (instancia LF).
-- GLOBAL > AMBITO (B2B, CLIENTE, BACKEND) > MODULO > PANTALLA > COMPONENTE.
-- Una regla se aplica a un nodo y la heredan sus descendientes. El nivel del hijo siempre es más profundo que el del padre (sin ciclos).
-- Se excluyen pantallas REEMPLAZADO/DESCARTADO/DUPLICADO. Las pantallas sin module_code se ubican por su flujo (nota en cada fila).
CREATE TABLE lf_ops.nucleo_nodos (
  codigo text PRIMARY KEY,
  padre text REFERENCES lf_ops.nucleo_nodos(codigo),
  nivel text NOT NULL,
  pantalla_id integer UNIQUE REFERENCES lf_ops.pantallas(id),
  nota text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT nucleo_nodos_nivel_valido CHECK (nivel IN ('GLOBAL','AMBITO','MODULO','PANTALLA','COMPONENTE')),
  CONSTRAINT nucleo_nodos_raiz_unica CHECK ((nivel = 'GLOBAL') = (padre IS NULL)),
  CONSTRAINT nucleo_nodos_pantalla_coherente CHECK ((nivel = 'PANTALLA') = (pantalla_id IS NOT NULL))
);
CREATE UNIQUE INDEX nucleo_nodos_una_raiz ON lf_ops.nucleo_nodos ((true)) WHERE nivel = 'GLOBAL';
COMMENT ON TABLE lf_ops.nucleo_nodos IS
  'Árbol de alcance del núcleo de reglas (instancia LF). Las reglas se aplican a un nodo y se heredan hacia abajo.';

CREATE OR REPLACE FUNCTION lf_ops.fn_nucleo_nodos_nivel_v1()
RETURNS trigger LANGUAGE plpgsql SET search_path = pg_catalog, lf_ops AS $$
DECLARE v_orden text[] := ARRAY['GLOBAL','AMBITO','MODULO','PANTALLA','COMPONENTE']; v_padre text;
BEGIN
  IF NEW.padre IS NOT NULL THEN
    SELECT nivel INTO v_padre FROM lf_ops.nucleo_nodos WHERE codigo = NEW.padre;
    IF array_position(v_orden, NEW.nivel) <= array_position(v_orden, v_padre) THEN
      RAISE EXCEPTION 'NUCLEO_NODO_NIVEL_INVALIDO: % (%) no puede colgar de % (%)', NEW.codigo, NEW.nivel, NEW.padre, v_padre;
    END IF;
  END IF;
  IF TG_OP = 'UPDATE' AND EXISTS (
       SELECT 1 FROM lf_ops.nucleo_nodos h
        WHERE h.padre = NEW.codigo
          AND array_position(v_orden, h.nivel) <= array_position(v_orden, NEW.nivel)) THEN
    RAISE EXCEPTION 'NUCLEO_NODO_NIVEL_INVALIDO: cambiar % a % deja hijos con nivel igual o superior', NEW.codigo, NEW.nivel;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_nucleo_nodos_nivel_v1 BEFORE INSERT OR UPDATE OF padre, nivel ON lf_ops.nucleo_nodos
  FOR EACH ROW EXECUTE FUNCTION lf_ops.fn_nucleo_nodos_nivel_v1();

REVOKE ALL ON TABLE lf_ops.nucleo_nodos FROM PUBLIC;
ALTER TABLE lf_ops.nucleo_nodos ENABLE ROW LEVEL SECURITY;
CREATE POLICY deny_direct_client_access ON lf_ops.nucleo_nodos
  AS PERMISSIVE FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);
REVOKE ALL ON lf_ops.nucleo_nodos FROM anon, authenticated;

INSERT INTO lf_ops.nucleo_nodos (codigo, padre, nivel, pantalla_id, nota) VALUES
  ('GLOBAL', NULL, 'GLOBAL', NULL, 'Raíz: todo LF'),
  ('B2B', 'GLOBAL', 'AMBITO', NULL, 'Portal Empresa y backoffice B2B'),
  ('CLIENTE', 'GLOBAL', 'AMBITO', NULL, 'Experiencia del cliente final'),
  ('BACKEND', 'GLOBAL', 'AMBITO', NULL, 'Procesos sin pantalla: integraciones, jobs, conciliación'),
  ('B2B_ADMINISTRACION', 'B2B', 'MODULO', NULL, 'Módulo B2B_ADMINISTRACION'),
  ('B2B_AUTENTICACION', 'B2B', 'MODULO', NULL, 'Módulo B2B_AUTENTICACION'),
  ('B2B_CARGAS', 'B2B', 'MODULO', NULL, 'Módulo B2B_CARGAS'),
  ('B2B_DASHBOARD', 'B2B', 'MODULO', NULL, 'Módulo B2B_DASHBOARD'),
  ('B2B_OFERTAS', 'B2B', 'MODULO', NULL, 'Módulo B2B_OFERTAS'),
  ('B2B_SIMULA', 'B2B', 'MODULO', NULL, 'Módulo B2B_SIMULA'),
  ('CLIENT_HOME', 'CLIENTE', 'MODULO', NULL, 'Módulo CLIENT_HOME'),
  ('CLIENT_LEGAL', 'CLIENTE', 'MODULO', NULL, 'Módulo CLIENT_LEGAL'),
  ('CLIENT_ONBOARDING', 'CLIENTE', 'MODULO', NULL, 'Módulo CLIENT_ONBOARDING'),
  ('CLIENT_PAYMENTS', 'CLIENTE', 'MODULO', NULL, 'Módulo CLIENT_PAYMENTS'),
  ('ONB_001', 'CLIENT_ONBOARDING', 'PANTALLA', 1, NULL),
  ('ONB_002', 'CLIENT_ONBOARDING', 'PANTALLA', 2, NULL),
  ('ONB_003', 'CLIENT_ONBOARDING', 'PANTALLA', 3, NULL),
  ('HOME_001', 'CLIENT_HOME', 'PANTALLA', 4, NULL),
  ('HOME_002', 'CLIENT_HOME', 'PANTALLA', 5, NULL),
  ('HOME_003', 'CLIENT_HOME', 'PANTALLA', 6, NULL),
  ('PASO3_SIN_OFERTA', 'CLIENT_HOME', 'PANTALLA', 7, 'derivado por flujo'),
  ('PASO3_OFERTA_UNICA_AMBAS', 'CLIENT_HOME', 'PANTALLA', 10, 'derivado por flujo'),
  ('PASO3_MULTI_OFERTA', 'CLIENT_HOME', 'PANTALLA', 11, NULL),
  ('PASO3_MODAL_CUOTAS', 'CLIENT_HOME', 'PANTALLA', 13, 'derivado por flujo'),
  ('PASO3_OFERTA_UNICA_PAGO_UNICO_V2', 'CLIENT_HOME', 'PANTALLA', 15, 'derivado por flujo'),
  ('PASO3_MODAL_DETALLE_PRECIO', 'CLIENT_HOME', 'PANTALLA', 16, 'derivado por flujo'),
  ('PASO3_CUOTAS_SELECCION', 'CLIENT_HOME', 'PANTALLA', 17, 'derivado por flujo'),
  ('PASO3_CUOTAS_DESGLOSE_V2', 'CLIENT_HOME', 'PANTALLA', 18, NULL),
  ('PASO3_OFERTA_UNICA_CUOTAS_V2', 'CLIENT_HOME', 'PANTALLA', 19, NULL),
  ('CHECKOUT_CUOTAS_MEDIO_PAGO', 'CLIENT_PAYMENTS', 'PANTALLA', 21, NULL),
  ('CHECKOUT_MODAL_CRONOGRAMA', 'CLIENT_PAYMENTS', 'PANTALLA', 24, NULL),
  ('CHECKOUT_ESTADO_ABRIENDO', 'CLIENT_PAYMENTS', 'PANTALLA', 25, NULL),
  ('CHECKOUT_ESTADO_CONFIRMANDO', 'CLIENT_PAYMENTS', 'PANTALLA', 27, NULL),
  ('CHECKOUT_ESTADO_YAPE_QR', 'CLIENT_PAYMENTS', 'PANTALLA', 28, NULL),
  ('CHECKOUT_ESTADO_TARJETA', 'CLIENT_PAYMENTS', 'PANTALLA', 30, NULL),
  ('CHECKOUT_PAGO_EXITOSO', 'CLIENT_PAYMENTS', 'PANTALLA', 33, NULL),
  ('CHECKOUT_ERROR_PAGO', 'CLIENT_PAYMENTS', 'PANTALLA', 34, NULL),
  ('PANT_LIBRO_RECLAMACIONES', 'CLIENT_LEGAL', 'PANTALLA', 36, 'derivado por flujo'),
  ('PANT_RESPALDO_CONFIANZA', 'CLIENT_HOME', 'PANTALLA', 37, 'derivado por flujo'),
  ('HOME_S9_FOOTER', 'CLIENT_HOME', 'PANTALLA', 38, 'derivado por flujo'),
  ('HOME_APRENDA_ANTES_DECIDIR', 'CLIENT_HOME', 'PANTALLA', 39, 'derivado por flujo'),
  ('HOME_RUTA_CLARIDAD', 'CLIENT_HOME', 'PANTALLA', 41, 'derivado por flujo'),
  ('HOME_FAQ', 'CLIENT_HOME', 'PANTALLA', 42, 'derivado por flujo'),
  ('B2B-CARGA-001', 'B2B_CARGAS', 'PANTALLA', 43, NULL),
  ('B2B-CARGA-002', 'B2B_CARGAS', 'PANTALLA', 44, NULL),
  ('B2B-CARGA-003', 'B2B_CARGAS', 'PANTALLA', 45, NULL),
  ('B2B-CARGA-004', 'B2B_CARGAS', 'PANTALLA', 46, NULL),
  ('B2B-CARGA-005', 'B2B_CARGAS', 'PANTALLA', 47, NULL),
  ('B2B-ADMIN-001', 'B2B_ADMINISTRACION', 'PANTALLA', 48, NULL),
  ('B2B-ADMIN-002', 'B2B_ADMINISTRACION', 'PANTALLA', 49, NULL),
  ('B2B-ADMIN-003', 'B2B_ADMINISTRACION', 'PANTALLA', 50, NULL),
  ('B2B-AUTH-001', 'B2B_AUTENTICACION', 'PANTALLA', 51, NULL),
  ('B2B-AUTH-002', 'B2B_AUTENTICACION', 'PANTALLA', 52, NULL),
  ('B2B-AUTH-003', 'B2B_AUTENTICACION', 'PANTALLA', 53, NULL),
  ('B2B-AUTH-004', 'B2B_AUTENTICACION', 'PANTALLA', 54, NULL),
  ('B2B-AUTH-006', 'B2B_AUTENTICACION', 'PANTALLA', 56, NULL),
  ('ONB_004', 'CLIENT_ONBOARDING', 'PANTALLA', 57, NULL),
  ('REC_001', 'CLIENT_ONBOARDING', 'PANTALLA', 58, NULL),
  ('CHECKOUT_PAGO_UNICO_MEDIO_PAGO', 'CLIENT_PAYMENTS', 'PANTALLA', 59, NULL),
  ('B2B-DASH-001', 'B2B_DASHBOARD', 'PANTALLA', 60, NULL),
  ('B2B-SIMULA-001', 'B2B_SIMULA', 'PANTALLA', 61, NULL),
  ('B2B-SIMULA-002', 'B2B_SIMULA', 'PANTALLA', 62, NULL),
  ('B2B-SIMULA-003', 'B2B_SIMULA', 'PANTALLA', 63, NULL),
  ('B2B-OFERTA-001', 'B2B_OFERTAS', 'PANTALLA', 64, NULL),
  ('B2B-SIMULA-004', 'B2B_SIMULA', 'PANTALLA', 65, NULL),
  ('B2B-CARGA-006', 'B2B_CARGAS', 'PANTALLA', 66, NULL),
  ('B2B-CARGA-007', 'B2B_CARGAS', 'PANTALLA', 67, NULL);
