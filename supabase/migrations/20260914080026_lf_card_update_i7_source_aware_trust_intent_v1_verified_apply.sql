do $apply$
declare v_body text; v_blob text;
begin
  select content into v_body from net._http_response where id=9885 and status_code=200 and error_msg is null;
  if v_body is null then raise exception 'I7_F04_VERIFIED_BODY_NOT_AVAILABLE'; end if;
  v_blob:=encode(extensions.digest(convert_to('blob '||octet_length(v_body)::text,'UTF8') || decode('00','hex') || convert_to(v_body,'UTF8'),'sha1'),'hex');
  if v_blob is distinct from '3f447b8ca14dcc29279b5800dacd81a332e2d4fe' then raise exception 'I7_F04_GIT_BLOB_MISMATCH expected=% actual=%','3f447b8ca14dcc29279b5800dacd81a332e2d4fe',v_blob; end if;
  execute v_body;
end;
$apply$;