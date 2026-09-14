-- LF_CARD_UPDATE_I7_SERVER_EVIDENCE_V3_VERIFIED_APPLY
-- Applies the exact already-fetched GitHub blob after cryptographic verification.
-- One-time governed materialization helper; no carrier/provider write.
do $apply$
declare
  v_body text;
  v_blob text;
begin
  select content into v_body
  from net._http_response
  where id=9884 and status_code=200 and error_msg is null;

  if v_body is null then
    raise exception 'I7_V3_VERIFIED_BODY_NOT_AVAILABLE';
  end if;

  v_blob:=encode(
    extensions.digest(
      convert_to('blob '||octet_length(v_body)::text,'UTF8') || decode('00','hex') || convert_to(v_body,'UTF8'),
      'sha1'
    ),
    'hex'
  );

  if v_blob is distinct from '2ab7f085be3e4617009bee0bdb27920b9750fb08' then
    raise exception 'I7_V3_GIT_BLOB_MISMATCH expected=% actual=%','2ab7f085be3e4617009bee0bdb27920b9750fb08',v_blob;
  end if;

  execute v_body;
end;
$apply$;
