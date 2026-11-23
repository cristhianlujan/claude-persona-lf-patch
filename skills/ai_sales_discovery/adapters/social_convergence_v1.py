"""SALY candidate-only social evidence convergence. No SQL/network/writes.

Normative production gates live outside this module: ACT-0001/Router, source rights,
identity binding, leases and a single governed writer. This module never authorizes them.
"""
from dataclasses import dataclass, field
from datetime import datetime, timezone
from hashlib import sha256
import json
from urllib.parse import urlsplit
from collections import defaultdict
from threading import Lock

KNOWN = {
    'FACEBOOK': {'facebook.com','www.facebook.com','m.facebook.com'},
    'INSTAGRAM': {'instagram.com','www.instagram.com'},
    'LINKEDIN': {'www.linkedin.com','linkedin.com'},
    'WEB': None,
    'NOTICIA': None,
    'REVISTA': None,
    'FORO': None,
    'MEDIO_DIGITAL': None,
}
STATES = {'ANUNCIADO', 'REALIZADO', 'IMPLEMENTADO', 'NO_DETERMINADO'}


def digest(obj):
    return sha256(json.dumps(obj, ensure_ascii=False, sort_keys=True, separators=(',',':')).encode('utf-8')).hexdigest()


def parse_dt(s):
    if s is None: return None
    if not isinstance(s, str): raise ValueError('PUBLISHED_TIMESTAMP_INVALID')
    try:
        dt=datetime.fromisoformat(s.replace('Z','+00:00'))
    except ValueError as e:
        raise ValueError('PUBLISHED_TIMESTAMP_INVALID') from e
    if dt.tzinfo is None: raise ValueError('PUBLISHED_TIMESTAMP_MISSING_TZ')
    return dt.astimezone(timezone.utc)


def normalize(row):
    required=('business_key','source','external_ref','url','event_key','claim_key','summary_non_personal','claim_state')
    if any(not isinstance(row.get(k),str) or not row[k].strip() for k in required):
        raise ValueError('CONTRACT_REQUIRED')
    src=row['source']; link=urlsplit(row['url'])
    if src not in KNOWN: raise ValueError('SOURCE_UNKNOWN')
    if link.scheme!='https' or not link.hostname or link.username or link.password or link.fragment:
        raise ValueError('SOURCE_URL_INVALID')
    hosts=KNOWN[src]
    if hosts is not None and link.hostname not in hosts: raise ValueError('SOURCE_HOST_MISMATCH')
    if row['claim_state'] not in STATES: raise ValueError('CLAIM_STATE_INVALID')
    if not row.get('company_identity_verified',False): raise ValueError('IDENTITY_UNVERIFIED')
    if row.get('matching_reviewed') is not True: raise ValueError('MATCHING_REVIEW_REQUIRED')
    dt=parse_dt(row.get('published_at'))
    if row.get('duration_ms') is not None and (isinstance(row['duration_ms'],bool) or not isinstance(row['duration_ms'],(int,float)) or row['duration_ms'] < 0):
        raise ValueError('DURATION_INVALID')
    if row.get('full_text') or row.get('media_bytes'): raise ValueError('RAW_OR_MEDIA_NOT_ADMITTED')
    x={k:row[k] for k in required}
    x.update({'published_at':dt.isoformat() if dt else None,
              'duration_ms':row.get('duration_ms'),
              'claimed_rights_ref':row.get('claimed_rights_ref'),
              'event_status':row['claim_state']})
    # La latencia y el recibo de captura NO forman parte de la identidad del post.
    # Reintentos con distintas duraciones deben seguir siendo idempotentes.
    x['sha256']=digest({k:x[k] for k in required + ('published_at',)})
    return x

@dataclass
class CandidateEngine:
    window_start: datetime
    window_end: datetime
    records: list=field(default_factory=list)
    concurrency: list=field(default_factory=list)
    logs: list=field(default_factory=list)
    _source_identity: dict=field(default_factory=dict)
    _event_claim: dict=field(default_factory=dict)
    _event_origins: dict=field(default_factory=dict)
    _lock: Lock=field(default_factory=Lock, repr=False)

    def __post_init__(self):
        if self.window_start.tzinfo is None or self.window_end.tzinfo is None or self.window_start >= self.window_end:
            raise ValueError('WINDOW_INVALID')
        self.window_start=self.window_start.astimezone(timezone.utc)
        self.window_end=self.window_end.astimezone(timezone.utc)

    def add(self, raw):
        x=normalize(raw)
        with self._lock:
            return self._add_serialized(x)

    def _add_serialized(self,x):
        dt=parse_dt(x['published_at'])
        if dt is None:
            self.logs.append({'source':x['source'], 'external_ref':x['external_ref'],'status':'HOLD_NO_DATE'})
            return 'HOLD_NO_DATE'
        if dt<self.window_start or dt>self.window_end:
            self.logs.append({'source':x['source'], 'external_ref':x['external_ref'],'status':'OUT_OF_WINDOW'})
            return 'OUT_OF_WINDOW'
        # One source publication has only one identity and one immutable digest.
        srcid=(x['business_key'],x['source'],x['external_ref'])
        if srcid in self._source_identity:
            original=self._source_identity[srcid]
            if original==x['sha256']:
                self.logs.append({'source':x['source'],'external_ref':x['external_ref'],'status':'SAME_SOURCE_REPLAY'})
                return 'SAME_SOURCE_REPLAY'
            self.logs.append({'source':x['source'],'external_ref':x['external_ref'],'status':'SOURCE_VERSION_CONFLICT'})
            return 'SOURCE_VERSION_CONFLICT'
        ev=(x['business_key'],x['event_key'])
        key=ev+(x['claim_key'],x['event_status'])
        previous=self._event_claim.get(key,[])
        if previous:
            original=self.records[previous[0]]
            if x['source']==original['source'] or any(self.records[i]['source']==x['source'] for i in previous):
                self._source_identity[srcid]=x['sha256']
                self.logs.append({'source':x['source'],'external_ref':x['external_ref'],'status':'DUPLICATE_WITHIN_CHANNEL','original_source_ref':original['external_ref']})
                return 'DUPLICATE_WITHIN_CHANNEL'
            # cross channel => record only minimal concurrence pointer. No repeated evidence.
            other=original['source']; original_ref=original['external_ref']
            self._source_identity[srcid]=x['sha256']
            self.concurrency.append({'business_key':x['business_key'],'event_key':x['event_key'],
                'claim_key':x['claim_key'],'source':x['source'],'source_ref':x['external_ref'],
                'original_source':other,'original_source_ref':original_ref,
                'concurrence':'CROSS_CHANNEL_DUPLICATE','source_url':x['url'],'observed_at':x['published_at']})
            self.logs.append({'source':x['source'],'external_ref':x['external_ref'],'status':'CROSS_CHANNEL_DUPLICATE','original_source':other})
            return 'CROSS_CHANNEL_DUPLICATE'
        # A genuinely new claim about an existing event complements it, not another event.
        event_seen=ev in self._event_origins
        original_ref=self._event_origins.get(ev)
        self._source_identity[srcid]=x['sha256']
        self._event_claim.setdefault(key,[]).append(len(self.records))
        if not event_seen:
            self._event_origins[ev]={'source':x['source'],'external_ref':x['external_ref']}
        self.records.append(x)
        if event_seen and original_ref['source']!=x['source']:
            self.concurrency.append({'business_key':x['business_key'],'event_key':x['event_key'],
                'claim_key':x['claim_key'],'source':x['source'],'source_ref':x['external_ref'],
                'original_source':original_ref['source'],'original_source_ref':original_ref['external_ref'],
                'concurrence':'CROSS_CHANNEL_COMPLEMENT','source_url':x['url'],'observed_at':x['published_at']})
        self.logs.append({'source':x['source'],'external_ref':x['external_ref'],'status':'ADMITTED_CANDIDATE'})
        return 'ADMITTED_CANDIDATE'

    def receipt(self):
        by_status={}
        for k,v in sorted(((k,sum(x['status']==k for x in self.logs)) for k in {x['status'] for x in self.logs})):
            by_status[k]=v
        durations=[x['duration_ms'] for x in self.records if x.get('duration_ms') is not None]
        return {'state':'CANDIDATE_READ_ONLY_NOT_DB_ADMITTED',
            'window_start':self.window_start.isoformat(),'window_end':self.window_end.isoformat(),
            'source_submissions':len(self.logs), 'unique_evidence_claims':len(self.records),
            'unique_events':len(self._event_origins),'concurrency_links':len(self.concurrency),
            'statuses':by_status,'observed_fetch_ms_total':sum(durations),
            'full_history_coverage':None,'source_end_confirmed':False,
            'db_write_confirmed':False,'sample_sha256':digest(self.records)}

    def validate_semantic_candidate(self, hypothesis):
        """Validate a downstream LLM suggestion against existing source claims. No scoring."""
        if not isinstance(hypothesis,dict) or not hypothesis.get('hypothesis') or not hypothesis.get('source_refs'):
            raise ValueError('SEMANTIC_CONTRACT')
        ids={(x['source'],x['external_ref']) for x in self.records}
        refs=hypothesis['source_refs']
        if not isinstance(refs,list) or len(refs)!=len({tuple(x) for x in refs}):
            raise ValueError('SEMANTIC_REFERENCES_DUPLICATE')
        if any(not isinstance(x,(list,tuple)) or len(x)!=2 or tuple(x) not in ids for x in refs):
            raise ValueError('SEMANTIC_SOURCE_NOT_PRESENT')
        if hypothesis.get('probability') is not None:
            raise ValueError('UNTRAINED_PROBABILITY_NOT_ALLOWED')
        return dict(hypothesis, status='CANDIDATE_FIELD_VALIDATION_REQUIRED', probability=None)