# Mini Judge

PASS only when:
- governing authority was read before the verdict;
- applicable EKB prevention was loaded;
- every material claim has direct readback;
- exact revision identity matches;
- structural identifiers were reconciled;
- no live authority conflict remains;
- no write/runtime/production authority is claimed.

Otherwise return the appropriate non-PASS status and blocking code.
