#!/usr/bin/env python3
"""Exercise the pairing protocol without a running system bus or hardware."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('bluetooth_helper', Path(__file__).parents[1] / 'scripts/bluetooth_helper.py')
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)

PATH = '/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF'

class Invocation:
    def __init__(self): self.value = self.error = None
    def return_value(self, value): self.value = value if value is not None else True
    def return_dbus_error(self, name, message): self.error = (name, message)

class Params:
    def __init__(self, *args): self.args = args
    def unpack(self): return self.args

class AgentTests(unittest.TestCase):
    def setUp(self):
        self.events = []
        self.old_emit = helper.emit
        helper.emit = lambda **event: self.events.append(event)
        self.agent = helper.Actions.__new__(helper.Actions)
        self.agent.bluez_owner = ':1.20'
        self.agent.pair_job = {'id': 1, 'path': PATH, 'action': 'pair'}
        self.agent.prompt = None
        self.agent.prompt_serial = 0
    def tearDown(self): helper.emit = self.old_emit
    def request(self, method, *args, sender=':1.20'):
        inv = Invocation()
        self.agent.agent_call(None, sender, None, None, method, Params(*args), inv)
        return inv
    def test_rejects_untrusted_sender_and_unselected_device(self):
        self.assertIsNotNone(self.request('RequestPinCode', PATH, sender=':1.21').error)
        self.assertIsNotNone(self.request('RequestPinCode', PATH.replace('hci0', 'hci1')).error)
        self.assertIsNone(self.agent.prompt)
    def test_validates_prompt_id_and_passkey(self):
        inv = self.request('RequestPasskey', PATH)
        prompt_id = self.agent.prompt[0]
        self.agent.answer({'promptId': prompt_id + 1, 'accept': True, 'value': '123'})
        self.agent.answer({'promptId': prompt_id, 'accept': True, 'value': '1234567'})
        self.agent.answer({'promptId': prompt_id, 'accept': True, 'value': '١٢'})
        self.assertIsNone(inv.value)
        self.agent.answer({'promptId': prompt_id, 'accept': True, 'value': '0042'})
        self.assertEqual(inv.value.unpack(), (42,))
        self.assertIsNone(self.agent.prompt)
    def test_pin_display_preserves_length_and_confirmation_is_padded(self):
        self.request('DisplayPinCode', PATH, '12')
        self.assertEqual(self.events[-1]['code'], '12')
        inv = self.request('RequestConfirmation', PATH, 42)
        self.assertEqual(self.events[-1]['code'], '000042')
        self.agent.answer({'promptId': self.agent.prompt[0], 'accept': False})
        self.assertEqual(inv.error[0], 'org.bluez.Error.Rejected')
    def test_malformed_request_is_generic(self):
        self.agent.command(['secret-pin'])
        self.assertEqual(self.events[-1], {'event': 'error', 'error': 'Invalid request'})
    def test_replacing_prompt_cancels_previous(self):
        old = self.request('RequestPinCode', PATH)
        self.request('RequestAuthorization', PATH)
        self.assertEqual(old.error[0], 'org.bluez.Error.Canceled')
        self.assertEqual(self.events[-1]['kind'], 'authorize')

if __name__ == '__main__': unittest.main()
