"""SQLite test of atomic one-use ledger behavior; not PostgreSQL DDL tests."""
import sqlite3
DB="""CREATE TABLE orders(id INTEGER PRIMARY KEY, message_id TEXT UNIQUE NOT NULL, scope_sha TEXT NOT NULL, actor TEXT NOT NULL, proposer TEXT NOT NULL, registrar TEXT NOT NULL, literal_sha TEXT NOT NULL, expires INTEGER NOT NULL, revoked INTEGER DEFAULT 0, consumed INTEGER DEFAULT 0);"""
NOW=100

def fixture(**patch):
    con=sqlite3.connect(':memory:')
    con.executescript(DB)
    if not patch.pop('omit',False):
        row=dict(id=1,message_id='user-msg-0001',scope_sha='a'*64,actor='owner-1',proposer='profile-1',registrar='orchestrator-1',literal_sha='b'*64,expires=NOW+15,revoked=0,consumed=0)
        row.update(patch)
        con.execute('INSERT INTO orders VALUES ('+','.join('?'*len(row))+')',tuple(row.values()))
        con.commit()
    return con

def consume(con,*,scope='a'*64,actor='owner-1',now=NOW):
    return con.execute('UPDATE orders SET consumed=1 WHERE id=1 AND scope_sha=? AND actor=? AND expires>? AND revoked=0 AND consumed=0 AND proposer<>registrar',(scope,actor,now)).rowcount==1

def test_happy_and_rollback():
    db=fixture();db.execute('BEGIN');assert consume(db);db.rollback();assert db.execute('SELECT consumed FROM orders').fetchone()[0]==0

def test_no_order(): assert not consume(fixture(omit=True))
def test_other_scope(): assert not consume(fixture(),scope='c'*64)
def test_expired(): assert not consume(fixture(expires=NOW-1))
def test_reused():
    db=fixture();db.execute('BEGIN');assert consume(db);assert not consume(db);db.rollback()
def test_revoked(): assert not consume(fixture(revoked=1))
def test_autoapproval(): assert not consume(fixture(registrar='profile-1'))
def test_wrong_owner(): assert not consume(fixture(),actor='model-1')
def test_rollback_stays_unconsumed():
    db=fixture();db.execute('BEGIN');assert consume(db);db.rollback();db.execute('BEGIN');assert consume(db);db.rollback()
