"""Validador del contrato de orden literal para orquestador LF.

NO recibe firmas. Solo puede ser usado para materializacion tras recibir
el evento USER del transporte protegido. El evento NO sale de un PR/prompt.
"""
import argparse
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path
if __package__ in (None, ''):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from scripts.lf_owner_chat_event_v1 import ChatOrderRejected, verify_order


def main(argv=None):
    p=argparse.ArgumentParser()
    p.add_argument('--orchestrator-user-event',required=True)
    p.add_argument('--exact-expected-scope',required=True)
    p.add_argument('--out-receipt',required=True)
    args=p.parse_args(argv)
    # Produced only by trusted orchestrator's PostgreSQL readback;
    # never accept owner_sub/repository/channel as per-order parameters.
    cfg_path=os.getenv('LF_OWNER_CHAT_CANONICAL_CONFIG_READBACK')
    if not cfg_path:
        raise ChatOrderRejected('CANONICAL_OWNER_CONFIG_READBACK_MISSING')
    cfg=json.loads(Path(cfg_path).read_text(encoding='utf-8'))
    if not isinstance(cfg,dict) or set(cfg)!={'source','config_key','owner_sub','repository_full_name','channel_code','fixed','authorized_accounts'} or cfg.get('source')!='private.lf_owner_chat_identity_v1' or cfg.get('config_key')!='LF_OWNER' or cfg.get('fixed') is not True:
        raise ChatOrderRejected('CANONICAL_OWNER_CONFIG_READBACK_INVALID')
    owner_sub=cfg['owner_sub']
    channel_code=cfg['channel_code']
    repository_full_name=cfg['repository_full_name']
    entries=cfg['authorized_accounts']
    if not isinstance(entries,list) or any(
        not isinstance(x,dict) or set(x)!={'channel_code','account_email_sha256','activo'}
        for x in entries
    ):
        raise ChatOrderRejected('CANONICAL_ACCOUNT_SESSION_READBACK_INVALID')
    accounts=tuple((x['channel_code'],x['account_email_sha256'],x['activo']) for x in entries)
    proposer=os.getenv('LF_OWNER_CHAT_PROPOSER_SUBJECT')
    registrar=os.getenv('LF_OWNER_CHAT_REGISTRAR_SUBJECT')
    ingress=os.getenv('LF_OWNER_CHAT_INGRESS')
    if ingress!='PROTECTED_ORCHESTRATOR_USER_EVENT' or not all((owner_sub,channel_code,proposer,registrar)):
        raise ChatOrderRejected('ORCHESTRATOR_INGRESS_NOT_ATTESTED')
    # Paths must be produced by the protected orchestrator and authoritative
    # HEAD/snapshot consumer, never by user-supplied PR content or the model.
    ev=json.loads(Path(args.orchestrator_user_event).read_text(encoding='utf-8'))
    scope=json.loads(Path(args.exact_expected_scope).read_text(encoding='utf-8'))
    receipt=verify_order(event=ev, expected_scope=scope, owner_sub=owner_sub, channel_code=channel_code, repository_full_name=repository_full_name,authorized_accounts=accounts,
                         proposer_subject=proposer, registrar_subject=registrar,
                         now=datetime.now(timezone.utc))
    Path(args.out_receipt).write_text(json.dumps(receipt,sort_keys=True,ensure_ascii=False)+'\n',encoding='utf-8')
    print(json.dumps({'status':'CHAT_OWNER_ORDER_VALIDATED_NOT_CONSUMED',
                      'scope_sha256':receipt['scope_sha256']},sort_keys=True))
    return 0


if __name__=='__main__':
    try: sys.exit(main())
    except (ChatOrderRejected,ValueError,OSError) as e:
        print('BLOCKED_CHAT_ORDER:'+str(e),file=sys.stderr)
        sys.exit(2)
