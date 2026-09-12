# Missing Input Policy

If authority, exact revision, or direct source access is missing, return `RETURN_TO_SOURCE_FOR_READBACK`.
If two live authorities conflict, return `BLOCK_PIPELINE`.
Never fill missing evidence from memory or plausibility.
