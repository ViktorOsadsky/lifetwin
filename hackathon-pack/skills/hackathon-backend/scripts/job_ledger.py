"""Small SQLite reference for local job idempotency and compare-and-swap states."""
import hashlib
import json
import sqlite3

TRANSITIONS = {
    'queued': {'running', 'cancelled'},
    'running': {'awaiting_approval', 'succeeded', 'failed', 'cancelled'},
    'awaiting_approval': {'ready', 'cancelled', 'failed'},
    'ready': {'executing', 'cancelled'},
    'executing': {'succeeded', 'failed', 'uncertain'},
    'uncertain': {'succeeded', 'failed'},
    'succeeded': set(), 'failed': set(), 'cancelled': set(),
}


class Ledger:
    def __init__(self, path):
        self.path = str(path)
        with self.connect() as db:
            db.execute('PRAGMA journal_mode=WAL')
            db.execute('CREATE TABLE IF NOT EXISTS jobs (key TEXT PRIMARY KEY, hash TEXT NOT NULL, state TEXT NOT NULL, revision INTEGER NOT NULL)')
            db.execute('CREATE TABLE IF NOT EXISTS events (key TEXT NOT NULL, revision INTEGER NOT NULL, state TEXT NOT NULL, UNIQUE(key, revision))')

    def connect(self):
        return sqlite3.connect(self.path, timeout=10)

    def reserve(self, key, payload):
        if not isinstance(key, str) or not key.strip():
            raise ValueError('A tenant-namespaced key is required')
        digest = hashlib.sha256(json.dumps(payload, sort_keys=True, separators=(',', ':'), allow_nan=False).encode()).hexdigest()
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            row = db.execute('SELECT hash,state,revision FROM jobs WHERE key=?', (key,)).fetchone()
            if row:
                if row[0] != digest: raise ValueError('idempotency_key_payload_conflict')
                return {'created': False, 'state': row[1], 'revision': row[2]}
            db.execute('INSERT INTO jobs VALUES (?,?,?,0)', (key, digest, 'queued'))
            db.execute('INSERT INTO events VALUES (?,0,?)', (key, 'queued'))
            return {'created': True, 'state': 'queued', 'revision': 0}

    def transition(self, key, expected_revision, target):
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            row = db.execute('SELECT state,revision FROM jobs WHERE key=?', (key,)).fetchone()
            if not row: raise KeyError(key)
            state, revision = row
            if type(expected_revision) is not int or revision != expected_revision:
                raise ValueError('stale_revision')
            if target not in TRANSITIONS[state]: raise ValueError('invalid_transition')
            db.execute('UPDATE jobs SET state=?,revision=? WHERE key=? AND revision=?', (target, revision + 1, key, revision))
            db.execute('INSERT INTO events VALUES (?,?,?)', (key, revision + 1, target))
            return {'state': target, 'revision': revision + 1}

    def history(self, key):
        with self.connect() as db:
            return db.execute('SELECT revision,state FROM events WHERE key=? ORDER BY revision', (key,)).fetchall()
