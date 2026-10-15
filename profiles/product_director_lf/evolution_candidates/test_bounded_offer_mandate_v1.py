import copy
import unittest
from bounded_offer_mandate_v1 import check_bounded_offer_mandate

SHA_A = "a"*64
SHA_B = "b"*64
TIME = "2026-10-14T16:00:00Z"
MANDATE = {
 "owner_id":"CURRENT_OWNER","obligation_id":"ONE","offer_id":"NEW_OFFER",
 "offer_version":"v2","signed_terms_sha256":SHA_A,
 "valid_from":"2026-10-01T00:00:00Z","valid_until":"2026-10-30T00:00:00Z",
 "verification_state":"VERIFIED","verification_receipt_ref":"verified://independent/1","active":True
}
OFFER = {
 "owner_id":"CURRENT_OWNER","obligation_id":"ONE","offer_id":"NEW_OFFER",
 "offer_version":"v2","terms_sha256":SHA_A,
 "eligible":True,"available":True,"matched":True,
}

class ScopedMandateTests(unittest.TestCase):
 def check(self,mandate=None,offer=None,owner="CURRENT_OWNER",when=TIME):
  return check_bounded_offer_mandate(
    copy.deepcopy(MANDATE if mandate is None else mandate),
    copy.deepcopy(OFFER if offer is None else offer),
    current_owner=owner,at=when)

 def test_exact_authorized_scope_is_eligible_proposal_only(self):
  r=self.check();self.assertEqual(r["decision"],"ELIGIBLE_FOR_SCOPED_PRESENTATION_IN_MODEL")
  self.assertFalse(r["backend_authorized"])
 def test_unrelated_obligation_is_blocked(self):
  v=copy.deepcopy(OFFER);v["obligation_id"]="TWO"
  self.assertIn("OBLIGATION_OUTSIDE_SCOPE",self.check(offer=v)["blocking_codes"])
 def test_old_offer_blocked(self):
  v=copy.deepcopy(OFFER);v["offer_id"]="OLD_OFFER"
  self.assertIn("OFFER_OUTSIDE_SCOPE",self.check(offer=v)["blocking_codes"])
 def test_wrong_offer_version_blocked(self):
  v=copy.deepcopy(OFFER);v["offer_version"]="v1"
  self.assertIn("VERSION_OUTSIDE_SCOPE",self.check(offer=v)["blocking_codes"])
 def test_terms_mutation_blocked_even_with_matching_offer(self):
  v=copy.deepcopy(OFFER);v["terms_sha256"]=SHA_B
  self.assertIn("SIGNED_TERMS_MISMATCH_OR_UNKNOWN",self.check(offer=v)["blocking_codes"])
 def test_missing_terms_blocked(self):
  v=copy.deepcopy(OFFER);v.pop("terms_sha256")
  self.assertIn("SIGNED_TERMS_MISMATCH_OR_UNKNOWN",self.check(offer=v)["blocking_codes"])
 def test_unknown_owner_blocked(self):
  self.assertIn("CURRENT_OWNER_SCOPE_MISMATCH",self.check(owner="OTHER")["blocking_codes"])
 def test_expired_mandate_blocked(self):
  self.assertIn("MANDATE_TIME_INVALID",self.check(when="2026-11-01T16:00:00Z")["blocking_codes"])
 def test_unverified_mandate_blocked(self):
  m=copy.deepcopy(MANDATE);m["verification_state"]="PENDING"
  self.assertIn("MANDATE_UNVERIFIED_OR_INACTIVE",self.check(mandate=m)["blocking_codes"])
 def test_no_verified_receipt_blocked(self):
  m=copy.deepcopy(MANDATE);m["verification_receipt_ref"]=""
  self.assertIn("MANDATE_UNVERIFIED_OR_INACTIVE",self.check(mandate=m)["blocking_codes"])
 def test_no_eligibility_blocks(self):
  v=copy.deepcopy(OFFER);v["eligible"]=False
  self.assertIn("OFFER_NOT_READY",self.check(offer=v)["blocking_codes"])
 def test_unmatched_offer_blocks(self):
  v=copy.deepcopy(OFFER);v["matched"]=False
  self.assertIn("OFFER_NOT_READY",self.check(offer=v)["blocking_codes"])
 def test_revoked_mandate_blocks(self):
  m=copy.deepcopy(MANDATE);m["active"]=False
  self.assertIn("MANDATE_UNVERIFIED_OR_INACTIVE",self.check(mandate=m)["blocking_codes"])
 def test_invalid_timestamp_blocks(self):
  self.assertIn("MANDATE_TIME_INVALID",self.check(when="not-a-date")["blocking_codes"])
 def test_missing_mandate_dict_blocks(self):
  self.assertEqual(self.check(mandate={})["decision"],"BLOCK")

if __name__=="__main__":
 unittest.main(verbosity=2)