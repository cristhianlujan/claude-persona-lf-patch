-- PE10_C3 v2 / CASO 201 / SQLite read-only synthetic fixture.
-- All identities and values are synthetic. Not LF production data.
PRAGMA foreign_keys = ON;
CREATE TABLE cargas (id TEXT PRIMARY KEY, fecha TEXT NOT NULL);
CREATE TABLE aprobaciones (id TEXT PRIMARY KEY, carga_id TEXT REFERENCES cargas(id), estado TEXT NOT NULL);
CREATE TABLE cartera (id TEXT PRIMARY KEY, carga_id TEXT REFERENCES cargas(id), ref_externa TEXT NOT NULL, titular TEXT NOT NULL);
CREATE TABLE ofertas (id TEXT PRIMARY KEY, obligacion_id TEXT REFERENCES cartera(id), estado TEXT NOT NULL);
CREATE TABLE pagos (id TEXT PRIMARY KEY, oferta_id TEXT REFERENCES ofertas(id), monto INTEGER NOT NULL, estado TEXT NOT NULL, fecha TEXT NOT NULL);
CREATE TABLE gateway (id TEXT PRIMARY KEY, pago_id TEXT REFERENCES pagos(id), ref_operacion TEXT NOT NULL, monto INTEGER NOT NULL, estado TEXT NOT NULL);
CREATE TABLE conciliaciones (id TEXT PRIMARY KEY, gateway_id TEXT REFERENCES gateway(id), obligacion_id TEXT REFERENCES cartera(id), ref_externa TEXT NOT NULL, estado TEXT NOT NULL);
CREATE TABLE bajas (id TEXT PRIMARY KEY, obligacion_id TEXT REFERENCES cartera(id), fecha TEXT NOT NULL);
CREATE TABLE liquidaciones (id TEXT PRIMARY KEY, obligacion_id TEXT REFERENCES cartera(id), monto INTEGER NOT NULL, fecha TEXT NOT NULL);
INSERT INTO cargas VALUES ('L1','2026-08-01'),('L2','2026-09-05'),('L3','2026-09-08');
INSERT INTO aprobaciones VALUES ('AP1','L1','APPROVED'),('AP2','L2','APPROVED'),('AP3','L3','APPROVED');
INSERT INTO cartera VALUES ('O1','L1','EXT-77','Y1'),('O2','L2','EXT-77','Y2'),('O3','L3','EXT-77','Y3'),('O4','L3','EXT-99','Y3');
INSERT INTO ofertas VALUES ('F1','O1','APPROVED'),('F2','O2','APPROVED'),('F3','O3','APPROVED'),('F4','O4','APPROVED');
INSERT INTO pagos VALUES ('P1','F1',120,'CONFIRMED','2026-10-03'),('P2','F2',80,'CONFIRMED','2026-10-04'),('P3','F3',35,'CONFIRMED','2026-09-29'),('P4','F4',10,'REJECTED','2026-10-03');
INSERT INTO gateway VALUES ('G1','P1','TX-101',120,'CONFIRMED'),('G2','P2','TX-102',80,'CONFIRMED'),('G3','P3','TX-103',35,'CONFIRMED');
INSERT INTO conciliaciones VALUES ('C1','G1','O1','EXT-77','MATCHED'),('C2','G2','O1','EXT-77','MATCHED'),('C3','G3','O1','EXT-77','MATCHED');
INSERT INTO liquidaciones VALUES ('LL1','O1',120,'2026-10-05');
-- No bajas exist in this fixture. Do not infer from empty rows that approval is missing.
