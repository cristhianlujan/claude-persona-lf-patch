#!/usr/bin/env python3
"""Offline negative tests for IG M10.13 registered historical exceptions."""
from __future__ import annotations
import importlib.util
from pathlib import Path
import sys
import unittest

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location("ig_m1013_full_verifier_under_test",
                                        HERE/"ig_m1013_full_current_validation_v1.py")
m=importlib.util.module_from_spec(spec)
sys.modules[spec.name]=m
spec.loader.exec_module(m)

class TestExactRegisteredDrift(unittest.TestCase):
    def fixture(self):
        local={};remote={};counts={};descriptions=[]
        for version,(original,sha16) in m.DUPLICATES.items():
            name="name_"+original
            hash_value="sha256:"+sha16+"0"*(64-len(sha16))
            local[original]=(name,None,"blob_"+original)
            remote[original]=(name,hash_value)
            remote[version]=(original+"_"+name,hash_value)
            counts[original]=counts[version]=1
            descriptions.append("| "+version+" |")
        for version,(name,blob) in m.LOCAL_ONLY.items():
            local[version]=(name,None,blob)
            descriptions.append(chr(96)+version+"_"+name+".sql"+chr(96))
        return local,remote,counts,"\n".join(descriptions)

    def verify(self,mutate=None,pin=None):
        local,remote,counts,text=self.fixture()
        if mutate is not None: mutate(local,remote,counts)
        m.check_inventory(local,remote,counts,text,
                          m.REGISTRY_GIT_BLOB if pin is None else pin)

    def test_valid_all_15(self): self.verify()
    def test_unknown_git_version_blocks(self):
        with self.assertRaisesRegex(m.FullParityError,"UNREGISTERED_DRIFT"):
            self.verify(lambda l,r,c: l.update({"20990101000000":("new",None,"a"*40)}))
    def test_unknown_database_version_blocks(self):
        with self.assertRaisesRegex(m.FullParityError,"UNREGISTERED_DRIFT"):
            self.verify(lambda l,r,c: (r.update({"20990101000000":("new","sha256:"+"a"*64)}),
                                        c.update({"20990101000000":1})))
    def test_duplicate_content_mutation_blocks(self):
        version=next(iter(m.DUPLICATES))
        with self.assertRaisesRegex(m.FullParityError,"DUPLICATE_SQL"):
            self.verify(lambda l,r,c: r.__setitem__(version,(r[version][0],"sha256:"+"f"*64)))
    def test_duplicate_name_mutation_blocks(self):
        version=next(iter(m.DUPLICATES))
        with self.assertRaisesRegex(m.FullParityError,"DUPLICATE_NAME"):
            self.verify(lambda l,r,c: r.__setitem__(version,("wrong",r[version][1])))
    def test_local_blob_mutation_blocks(self):
        version=next(iter(m.LOCAL_ONLY))
        with self.assertRaisesRegex(m.FullParityError,"GIT_ONLY_SOURCE"):
            self.verify(lambda l,r,c: l.__setitem__(version,(l[version][0],None,"f"*40)))
    def test_unmatched_statement_count_blocks(self):
        version=next(iter(m.DUPLICATES))
        with self.assertRaisesRegex(m.FullParityError,"STATEMENT_COVERAGE"):
            self.verify(lambda l,r,c: c.pop(version))
    def test_statement_count_drift_blocks(self):
        version=next(iter(m.DUPLICATES))
        with self.assertRaisesRegex(m.FullParityError,"DUPLICATE_SQL"):
            self.verify(lambda l,r,c: c.__setitem__(version,2))
    def test_registry_pin_drift_blocks(self):
        with self.assertRaisesRegex(m.FullParityError,"REGISTRY_BLOB"):
            self.verify(pin="f"*40)
    def raw_fixture(self):
        proof={}
        for duplicate,(original,sha16) in m.DUPLICATES.items():
            full_digest=sha16+"0"*(64-len(sha16))
            proof[duplicate]=(full_digest,1)
            proof[original]=(full_digest,1)
        return proof

    def test_snapshot_canonical_hash_can_differ_from_raw(self):
        local,remote,counts,registry=self.fixture()
        for version,(original,_pin) in m.DUPLICATES.items():
            canonical="sha256:"+"f"*64
            remote[version]=(remote[version][0],canonical)
            remote[original]=(remote[original][0],canonical)
        m.check_inventory(local,remote,counts,registry,m.REGISTRY_GIT_BLOB)
        m.check_raw_duplicates(self.raw_fixture())

    def test_raw_digest_pin_mismatch_rejected(self):
        proof=self.raw_fixture()
        first=next(iter(m.DUPLICATES))
        proof[first]=("f"*64,1)
        with self.assertRaisesRegex(m.FullParityError,"DUPLICATE_RAW_SQL"):
            m.check_raw_duplicates(proof)

    def test_raw_cardinality_mismatch_rejected(self):
        proof=self.raw_fixture()
        first=next(iter(m.DUPLICATES))
        proof[first]=(proof[first][0],2)
        with self.assertRaisesRegex(m.FullParityError,"DUPLICATE_RAW_SQL"):
            m.check_raw_duplicates(proof)

    def test_missing_raw_pair_rejected(self):
        proof=self.raw_fixture()
        proof.pop(next(iter(proof)))
        with self.assertRaisesRegex(m.FullParityError,"DUPLICATE_RAW_COVERAGE"):
            m.check_raw_duplicates(proof)

    def test_pointer_syntax_strict(self):
        version="20261009172500"
        good=("github://cristhianlujan/claude-persona-lf-patch@"+("a"*40)+
              "/supabase/migrations/"+version+"_ig_m713_contract_and_criteria_controls_v1.sql"+
              "#blob="+m.POINTERS[version])
        self.assertIsNotNone(m.POINTER_RE.fullmatch(good))
        self.assertIsNone(m.POINTER_RE.fullmatch(good.replace("cristhianlujan","different")))
        self.assertIsNone(m.POINTER_RE.fullmatch(good.replace("#blob=","#untrusted=")))

if __name__=="__main__":
    unittest.main()
