-- LF PE10 / work 1133 / metadata evidence association ONLY (not method execution or DONE).
-- Source-first via LF Migration Merge Train. Fail-closed prestate, exact 32 checkpoint IDs.
-- The RAW archive is a ChatGPT conversation attachment, not Git or a provider-attested receipt.
-- No changes to method definitions, runtime, product data, status or assertion receipts.
DO $pe10_evidence$
DECLARE
 v_work_id bigint;
 v_n integer;
 v_manifest_uri constant text := 'github://cristhianlujan/claude-persona-lf-patch/docs/profile_updater/experiments/pe10_methods32_p0/raw_evidence_manifest_v1.json';
 v_archive_sha constant text := '8142626c361e29a0b696126048783c672f8457d00dc7e62f22d9b415fa3aecba';
 v_file_id constant text := 'file_000000004e48820e8414025654581746';
BEGIN
 SELECT id INTO STRICT v_work_id
 FROM programacion.engineering_work_items
 WHERE id=1133 AND work_code='PEVO-PE10-METHODS32-P0'
   AND status='BACKLOG';
 IF (SELECT count(*) FROM programacion.pe10_method_variants
     WHERE case_ref='PE10-IG-M107-M109-P0') <> 32
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=v_work_id AND status='PENDING'
       AND evidence_ref IS NULL AND assertion_receipt IS NULL) <> 32
 OR EXISTS (SELECT 1 FROM programacion.engineering_work_updates WHERE work_item_id=v_work_id)
 THEN RAISE EXCEPTION 'PE10_EVIDENCE_PRESTATE_DRIFT'; END IF;

 CREATE TEMP TABLE pe10_evidence_map (
   method_code text PRIMARY KEY, checkpoint_id bigint UNIQUE NOT NULL,
   raw_path text NOT NULL, raw_sha256 text NOT NULL
 ) ON COMMIT DROP;
 INSERT INTO pe10_evidence_map (method_code,checkpoint_id,raw_path,raw_sha256)
 VALUES
    ('PE10_M01',1625,'prior_originals/PE10_M01_RAW.json','58667ea7e8abec32c52e1495cff2eb9c6da1b8c62dce10cbc6464071cc04bc96'),
    ('PE10_M02',1626,'prior_originals/PE10_M02_RAW.json','34cdfe2c2d3619495122092934d2db7719a312d620094b97463d1c41866c54e7'),
    ('PE10_M03',1627,'methods/PE10_M03.json','35c677ff8ba29da910a88b4c2f28fa1905a2723bd9608f60d8405f5eb6d7adea'),
    ('PE10_M04',1628,'methods/PE10_M04.json','4ec684e46bb3b6ed25a0dd18919f632aacca3b2ea5db7dce9dfd120b21941bfd'),
    ('PE10_M05',1629,'methods/PE10_M05.json','8fefae266b4b2279cb8d921dd4b2893ac607993fd38ae70c72d6f3f0bf050685'),
    ('PE10_M06',1630,'methods/PE10_M06.json','21d4e22c04f2f5b1dee4216807f9466a4a55fbf49d91e174f440d7e76280b5d4'),
    ('PE10_M07',1631,'methods/PE10_M07.json','518a7e53245608950e5681a5cca655998ac8913dcec718918bf490495d8ea421'),
    ('PE10_M08',1632,'methods/PE10_M08.json','197bba20c5ac02a7bc0a70e43246499798af8fcca068c091eda6f9df165befd1'),
    ('PE10_M09',1633,'methods/PE10_M09.json','49b6c91b84756fe18bf79374275d51be3b33dd5879969898b60e8a3a4e71865a'),
    ('PE10_M10',1634,'methods/PE10_M10.json','f7a3a2979c0e8094f3168ac0b5f6d4d8f9902f1664dc5529cc7a88c53789e3d6'),
    ('PE10_M11',1635,'methods/PE10_M11.json','2e96a42a53379abc98ce503a60db4fabedfdb68f222605b137618fa9ca5872be'),
    ('PE10_M12',1636,'methods/PE10_M12.json','04392fbcd8e40c7236abef2b7019b2668efd8ff5e46bb50765f9f384b5ef78a3'),
    ('PE10_M13',1637,'methods/PE10_M13.json','ed1b41639150ea4c775c2ed17b44867b7a3e2fdfa89588bdbe950beb436b03b6'),
    ('PE10_M14',1638,'methods/PE10_M14.json','4809575beee9815347ce3e53da9c8c68f99d6b3ae13aee9915954daf7153c686'),
    ('PE10_M15',1639,'methods/PE10_M15.json','cceaeb904bad988a95be757f2bd7b5bad048f27d489ca6bc41f46ccc3f388dcb'),
    ('PE10_M16',1640,'methods/PE10_M16.json','aa4c29172f6355e748f15b0fb6d3d4e3e2f1f2b358f2de63b293ee8837a0dda3'),
    ('PE10_M17',1641,'methods/PE10_M17.json','105a7dddfb5ba49ee5b29e3c63f1c215f820fd7505ef0bd1c9a8a67ec1ad93f5'),
    ('PE10_M18',1642,'methods/PE10_M18.json','ea756fb0573ff82a29d1d9c9bdeff65c2ab0723420859e43b11ac0930179e379'),
    ('PE10_M19',1643,'methods/PE10_M19.json','13a3c0278e78c8ffe8b4ebbd44c084c972277ac3d8fe06a6fb5c027e0fa80ce1'),
    ('PE10_M20',1644,'methods/PE10_M20.json','5fdb1e282b3ff7e425b29c89440ac3ee5bffaa390930e0202775e1c77918cc63'),
    ('PE10_M21',1645,'methods/PE10_M21.json','af542c5af8974415367758c6312e860168b34425b49f42f3d073074ea214cf60'),
    ('PE10_M22',1646,'methods/PE10_M22.json','bbb21bd84ec17a11326d6555e4b1536936ac159493cf1750916fb5365f3a3ad8'),
    ('PE10_M23',1647,'methods/PE10_M23.json','bcdc0f50dec580977aeae18ffd3d89a340d57c766fe0059d790e2b62beeae461'),
    ('PE10_M24',1648,'methods/PE10_M24.json','9fa8e95b882eafad85549b252f0016c880ee8f74b793152316f8e59d1c16063d'),
    ('PE10_M25',1649,'methods/PE10_M25.json','b0809de7b913badea7b7b34e223ec85ed91bd9d7a7443e23e414956a25c22ed7'),
    ('PE10_M26',1650,'methods/PE10_M26.json','2fc474fa158c7d6c06f553a0e5374ac17980bff0cd31a231a7a2030c24b11bb3'),
    ('PE10_M27',1651,'methods/PE10_M27.json','1dcf87203fe4ba824afef76c88a88197d3a141791ea1fefab4e888196129de3f'),
    ('PE10_M28',1652,'methods/PE10_M28.json','9ec2cdd1b2b838779f4f04c29643fc5c87542b8ba40d1deed06ebb122a928204'),
    ('PE10_M29',1653,'methods/PE10_M29.json','84db22f2238f703f5c7edab7e8a09432021aa05c2344bb4231e5a39e120b9ce0'),
    ('PE10_M30',1654,'methods/PE10_M30.json','1360b569f3bc3a72a15760f59775f050eccb93e9de426425f8a1aa85f036813f'),
    ('PE10_M31',1655,'methods/PE10_M31.json','cf7dac18b4fcab83f4cf9463ece3468c0d48a96e6da21de83a42dac34f7b9d56'),
    ('PE10_M32',1656,'methods/PE10_M32.json','65dc403d6b5d2a1210fc28ffb54afd1030dda46ac2d550879417b0217886b410');
 IF (SELECT count(*) FROM pe10_evidence_map) <> 32
 OR EXISTS (SELECT 1 FROM pe10_evidence_map WHERE raw_sha256 !~ '^[a-f0-9]{64}$')
 OR EXISTS (
   SELECT 1 FROM pe10_evidence_map m
   LEFT JOIN programacion.engineering_work_checkpoints c
     ON c.id=m.checkpoint_id AND c.work_item_id=v_work_id
     AND c.checkpoint_code=m.method_code AND c.status='PENDING'
   WHERE c.id IS NULL
 )
 THEN RAISE EXCEPTION 'PE10_EVIDENCE_SOURCE_INDEX_INCONSISTENT'; END IF;

 UPDATE programacion.engineering_work_checkpoints c
 SET evidence_ref='chatgpt-file://' || v_file_id || '/' || m.raw_path
                 || '#sha256=' || m.raw_sha256
 FROM pe10_evidence_map m
 WHERE c.id=m.checkpoint_id AND c.work_item_id=v_work_id
   AND c.checkpoint_code=m.method_code
   AND c.status='PENDING' AND c.evidence_ref IS NULL;
 GET DIAGNOSTICS v_n=ROW_COUNT;
 IF v_n<>32 THEN RAISE EXCEPTION 'PE10_EVIDENCE_LINK_COUNT_MISMATCH:%',v_n; END IF;

 INSERT INTO programacion.engineering_work_updates (
   work_item_id,update_type,summary,detail,next_action,evidence_refs,
   reported_by,observed_at
 )
 SELECT v_work_id, 'DELIVERY',
        'PE10 '||m.method_code||' RAW source indexed (not completed)',
        'Raw SHA256='||m.raw_sha256||'; archive SHA256='||v_archive_sha
          ||'; evidence is local/attachment provenance, NOT independently verified, not a governed assertion receipt',
        'Verify RAW via governed provider; maintain PENDING until genuine execution/contract closure',
        jsonb_build_array(v_manifest_uri||'#'||m.method_code,
          'chatgpt-file://' || v_file_id || '/' || m.raw_path || '#sha256=' || m.raw_sha256),
        'LF_MIGRATION_TRAIN_SOURCE_PE10_EVIDENCE_V1',clock_timestamp()
 FROM pe10_evidence_map m ORDER BY m.method_code;
 GET DIAGNOSTICS v_n=ROW_COUNT;
 IF v_n<>32 THEN RAISE EXCEPTION 'PE10_EVIDENCE_AUDIT_COUNT_MISMATCH:%',v_n; END IF;

 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=v_work_id AND status='PENDING'
       AND evidence_ref IS NOT NULL AND assertion_receipt IS NULL
       AND completed_at IS NULL) <>32
 OR (SELECT count(*) FROM programacion.engineering_work_updates
     WHERE work_item_id=v_work_id AND update_type='DELIVERY')<>32
 OR (SELECT status FROM programacion.engineering_work_items WHERE id=v_work_id)<>'BACKLOG'
 THEN RAISE EXCEPTION 'PE10_EVIDENCE_POSTSTATE_INVALID'; END IF;
END $pe10_evidence$;
