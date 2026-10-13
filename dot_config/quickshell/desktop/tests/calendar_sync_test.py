"""Calendar API/cache regression checks; no Google credentials are used."""
import copy
import importlib.util
import io
import json
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from datetime import datetime, timezone
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch
from zoneinfo import ZoneInfo

sys.dont_write_bytecode = True
scripts = Path(__file__).resolve().parents[1] / 'scripts/calendar-sync'
sys.path.insert(0, str(scripts))
from omarchy_calendar_sync import cli, config, contract, normalize
from omarchy_calendar_sync.gws import Gws, GwsApiError, GwsAuthError
from omarchy_calendar_sync.storage import cache_lock, write_atomic
spec = importlib.util.spec_from_file_location('calendar_actions', scripts / 'action.py')
actions = importlib.util.module_from_spec(spec)
spec.loader.exec_module(actions)

CAL = dict(id='one', name='Personal', color='#123456', primary=True, accessRole='owner')
EVENT = dict(id='event', summary='Original', start={'dateTime':'2026-10-12T09:00:00+05:30'}, end={'dateTime':'2026-10-12T10:00:00+05:30'})
TZ = ZoneInfo('Asia/Colombo')

class Client:
    def __init__(self, error=None, result=None):
        self.error, self.result, self.calls = error, result, []
    def calendars(self): return [CAL]
    def mutate(self, operation, calendar_id, event_id=None, body=None):
        self.calls.append((operation, calendar_id, event_id, body))
        if self.error: raise self.error
        return copy.deepcopy(self.result or EVENT)

class CalendarTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name)/'events.json'
        rows = normalize.normalize_event(EVENT, CAL, TZ)
        rows += normalize.normalize_event(EVENT, dict(CAL, id='two'), TZ)
        self.document = contract.build_document(rows, '2026-10-12T00:00:00Z', 'test')
        write_atomic(self.path, self.document)
    def args(self, command, **changes):
        value = dict(command=command, calendar='one', id='event', title='Changed', location=None,
                     date=None, start=None, end=None, all_day=False)
        value.update(changes)
        return SimpleNamespace(**value)
    def perform(self, args, client): actions.perform(args, client, self.path, TZ)
    def read(self): return json.loads(self.path.read_text())

    def test_failed_mutations_preserve_cache(self):
        for command in ('create','edit','delete'):
            args = self.args(command, date='2026-10-12', start='11:00', end='12:00')
            with self.assertRaises(GwsApiError): self.perform(args, Client(error=GwsApiError('denied')))
            self.assertEqual(self.read(), self.document)
    def test_delete_is_scoped_to_calendar(self):
        self.perform(self.args('delete'), Client())
        self.assertEqual([e['calendarId'] for e in self.read()['events']], ['two'])
    def test_edit_rebuilds_day_rows_and_preserves_other_calendar(self):
        result = dict(EVENT, summary='Changed', start={'dateTime':'2026-10-13T23:00:00+05:30'}, end={'dateTime':'2026-10-14T01:00:00+05:30'})
        client = Client(result=result)
        self.perform(self.args('edit', date='2026-10-13', start='23:00', end='23:30'), client)
        self.assertEqual([e['dateKey'] for e in self.read()['events'] if e['calendarId']=='one'], ['2026-10-13','2026-10-14'])
        self.assertEqual([e['title'] for e in self.read()['events'] if e['calendarId']=='two'], ['Original'])
        self.assertIn('start', client.calls[0][3])
    def test_title_only_edit_preserves_all_day_duration(self):
        result = dict(EVENT, summary='Changed', start={'date':'2026-10-12'}, end={'date':'2026-10-15'})
        client=Client(result=result)
        self.perform(self.args('edit'), client)
        self.assertEqual(client.calls[0][3], {'summary':'Changed'})
        self.assertEqual(len([e for e in self.read()['events'] if e['calendarId']=='one']),3)
    def test_primary_create_resolves_actual_calendar_id(self):
        client=Client()
        self.perform(self.args('create', calendar='primary', date='2026-10-12', start='09:00', end='10:00'),client)
        self.assertEqual(client.calls[0][1], 'one')
        self.assertFalse(any(e['id'].startswith('local-') for e in self.read()['events']))
    def test_invalid_times_do_not_mutate_google(self):
        for changes in (dict(start='25:00',end='26:00'), dict(start='11:00',end='10:00')):
            client=Client()
            with self.assertRaises(ValueError): self.perform(self.args('create',date='2026-10-12',**changes), client)
            self.assertEqual(client.calls,[])
    def test_read_only_calendar_is_rejected(self):
        client=Client();client.calendars=lambda:[dict(CAL, accessRole='reader')]
        with self.assertRaises(ValueError): self.perform(self.args('delete'),client)
        self.assertEqual(client.calls,[])
    def test_cli_uses_configured_binary_and_profile(self):
        cfg=Path(self.temp.name)/'config.json';cfg.write_text(json.dumps(dict(profile='/fake/profile',gwsPath='/fake/gws')))
        with patch.object(actions,'Gws') as constructor, patch.object(actions,'perform'), redirect_stdout(io.StringIO()):
            self.assertEqual(actions.main(['--config',str(cfg),'delete','--id','event']),0)
        constructor.assert_called_once_with('/fake/profile',binary='/fake/gws')
    def test_lock_has_bounded_wait(self):
        with cache_lock(self.path):
            with self.assertRaises(TimeoutError):
                with cache_lock(self.path, timeout=0): pass
    def test_failed_sync_preserves_cache(self):
        class Failed:
            def check(self): raise GwsApiError('failure')
        with redirect_stderr(io.StringIO()): self.assertEqual(cli.run(Failed(),config.DEFAULTS,datetime.now(timezone.utc),self.path,TZ),1)
        self.assertEqual(self.read(),self.document)
    def test_dst_all_day_and_midnight_boundaries(self):
        tz=ZoneInfo('America/New_York')
        rows=normalize.normalize_event(dict(EVENT,start={'date':'2026-03-07'},end={'date':'2026-03-10'}), CAL,tz)
        self.assertEqual([r['dateKey'] for r in rows],['2026-03-07','2026-03-08','2026-03-09'])
        rows=normalize.normalize_event(dict(EVENT,start={'dateTime':'2026-03-09T23:00:00-04:00'},end={'dateTime':'2026-03-10T00:00:00-04:00'}),CAL,tz)
        self.assertEqual(len(rows),1)

class AdapterTests(unittest.TestCase):
    def test_calendar_and_event_pagination(self):
        for listing in ('calendars','events'):
            calls=[]
            def runner(argv,env):
                calls.append(argv)
                item = dict(CAL) if listing=='calendars' else dict(EVENT)
                item['id']=str(len(calls))
                return 0,json.dumps(dict(items=[item],**({'nextPageToken':'page2'} if len(calls)==1 else {}))),''
            client=Gws('/fake',runner=runner)
            rows=client.calendars() if listing=='calendars' else client.events('one','min','max')
            self.assertEqual(len(rows),2)
            self.assertEqual(json.loads(calls[1][-1])['pageToken'],'page2')
    def test_http_error_even_with_zero_exit_is_failure(self):
        for code in (0,1):
            client=Gws('/fake',runner=lambda *args:(code,'{"error":{"code":403,"message":"denied"}}',''))
            with self.assertRaises(GwsAuthError): client.mutate('insert','one',body={})
    def test_empty_successful_delete(self):
        self.assertEqual(Gws('/fake',runner=lambda *a:(0,'','')).mutate('delete','one','event'),{})
    def test_timeout_is_reported(self):
        def runner(*a): raise subprocess.TimeoutExpired('gws',25)
        with self.assertRaises(GwsApiError): Gws('/fake',runner=runner).calendars()
    def test_version_is_read_once(self):
        calls=[]
        def runner(*a): calls.append(a);return 0,'gws 0.22.5',''
        client=Gws('/fake',runner=runner)
        client.check();client.version()
        self.assertEqual(len(calls),1)

if __name__=='__main__': unittest.main()
