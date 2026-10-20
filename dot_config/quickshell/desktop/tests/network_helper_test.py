"""Isolated subprocess tests; all network executables are fakes."""
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time
import unittest

HELPER = Path(__file__).resolve().parents[1] / "scripts" / "network_helper.py"


class NetworkHelperTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="qs-network-helper-")
        self.root = Path(self.tmp.name)
        self.log = self.root / "argv.jsonl"
        self.marker = self.root / "marker"
        self.fake = self.root / "fake"
        self.fake.write_text(r'''#!/usr/bin/env python3
import json, os, signal, subprocess, sys, time
a=sys.argv[1:]
with open(os.environ['LOG'],'a') as f: f.write(json.dumps(a)+'\n')
mode=os.environ.get('MODE','ok')
if mode=='leader-exit':
    p=subprocess.Popen([sys.executable,'-c',"import signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(60)"], start_new_session=os.environ.get('ESCAPE')=='1')
    open(os.environ['DESC'],'w').write(str(p.pid)); sys.exit(0)
if mode=='hang':
    if os.environ.get('DESC'):
        p=subprocess.Popen([sys.executable,'-c',"import signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(60)"], start_new_session=os.environ.get('ESCAPE')=='1')
        open(os.environ['DESC'],'w').write(str(p.pid))
    time.sleep(60)
if mode=='fail': print('Operation failed',file=sys.stderr); sys.exit(1)
if mode=='auth': print('Authentication failed',file=sys.stderr); sys.exit(1)
cmd=a if a and a[0] in ('-j','-n') else []; i=0
while not cmd and i<len(a) and a[i]!='--':
 if a[i]=='--dont-ask': i+=1
 elif a[i]=='--passphrase': i+=2
 else: raise SystemExit('unexpected global option '+a[i])
if not cmd and i<len(a): cmd=a[i+1:]
if cmd[:2]==['device','list']:
 if mode=='bad-devices': print('not a device table')
 elif mode=='empty-devices': print('Devices\n Name        Address             Powered  Adapter  Mode')
 else: print('\x1b[1mDevices\x1b[0m\n Name        Address             Powered  Adapter  Mode\n ------------------------------------------------------\n wlp2s0      aa:bb:cc:dd:ee:ff   '+('off' if mode=='radio-off' else 'on')+'       phy0     station')
elif cmd[:3]==['device','wlp2s0','show']: print('Powered                 '+('off' if mode=='radio-off' else 'on')+'\nScanning                no')
elif cmd[:2]==['known-networks','list']:
 if mode=='bad-known': print('broken saved-network output')
 else: print('\x1b[1mKnown networks\x1b[0m\n Name                  Security        Last connected\n ------------------------------------------------------\n Coffee Shop           psk             yesterday\n X  ;  $(hi)           psk             today')
elif cmd[:3]==['known-networks','Coffee Shop','show']: print('         *  AutoConnect             yes')
elif cmd[-2:]==['get-networks','rssi-dbms']:
 if mode=='bad-networks': print('not a network table')
 else: print('\x1b[1mAvailable networks\x1b[0m\n\x1b[1m Network name          Security        Signal\x1b[0m\n ------------------------------------------------------\n > Coffee Shop         psk             -5500\n   X  ;  $(hi)         8021x           -7000\n > >literal            wep             -8000 dBm')
elif cmd==['station','wlp2s0','show'] and os.environ.get('SCAN_COUNT'):
 cfile=os.environ['SCAN_COUNT']; n=int(open(cfile).read()) if os.path.exists(cfile) else 0; open(cfile,'w').write(str(n+1)); print('Connected network       Coffee Shop\nScanning                '+('yes' if n==0 else 'no'))
elif cmd[-1:]==['show']: print('Connected network       Coffee Shop\nScanning                no')
elif cmd[-1:]==['scan']: print('')
elif cmd[:5]==['-j','-4','route','get','1.1.1.1']:
 if os.environ.get('ROUTE_DELAY'): time.sleep(float(os.environ['ROUTE_DELAY']))
 print(os.environ.get('ROUTE','[{"dev":"wlp2s0","prefsrc":"10.1.0.2","gateway":"10.1.0.1"}]'))
elif cmd and cmd[0]=='-n':
 if os.environ.get('PING_DELAY'): time.sleep(float(os.environ['PING_DELAY']))
 if mode=='ping-error': print('ping: unknown option',file=sys.stderr); sys.exit(2)
 if mode=='ping-loss': print('1 packets transmitted, 0 received, 100% packet loss'); sys.exit(1)
 print('time=12.5 ms')
''')
        self.fake.chmod(0o755)
        self.env = os.environ.copy()
        self.env.update(NETWORK_HELPER_IWCTL=str(self.fake), NETWORK_HELPER_IP=str(self.fake),
                        NETWORK_HELPER_PING=str(self.fake), NETWORK_HELPER_PROC_NET_DEV=str(self.root/'netdev'),
                        NETWORK_HELPER_DEADLINE_SCALE='1', LOG=str(self.log))
        (self.root/'netdev').write_text('Inter-| Receive | Transmit\n face |bytes packets errs drop fifo frame compressed multicast|bytes packets errs drop fifo colls carrier compressed\n wlp2s0: 123 0 0 0 0 0 0 0 456 0 0 0 0 0 0 0\n eth0: 123 0 0 0 0 0 0 0 456 0 0 0 0 0 0 0\n tun0: 123 0 0 0 0 0 0 0 456 0 0 0 0 0 0 0\n')

    def tearDown(self):
        self.tmp.cleanup()

    def invoke(self, req, *, raw=None, timeout=8, env=None):
        p = subprocess.run(['python3', str(HELPER)], input=raw if raw is not None else json.dumps(req),
                           text=True, capture_output=True, env=env or self.env, timeout=timeout)
        return json.loads(p.stdout), p

    def assertGone(self, pid):
        until=time.monotonic()+1
        while time.monotonic()<until:
            if not Path(f'/proc/{pid}').exists(): return
            time.sleep(.02)
        self.fail(f'owned child {pid} still exists (including zombie)')

    def argv(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def test_real_tables_known_spaces_active_and_raw_rssi(self):
        out, _ = self.invoke({'op':'state'})
        self.assertTrue(out['ok'], out)
        self.assertEqual([n['ssid'] for n in out['networks']], ['Coffee Shop','>literal','X  ;  $(hi)'])
        self.assertEqual(out['networks'][0]['signal'], 90)
        self.assertTrue(out['networks'][0]['inUse'])
        self.assertTrue(out['networks'][0]['known'])
        self.assertEqual(out['networks'][1]['security'], 'wep')
        self.assertEqual(out['networks'][2]['security'], '8021x')
        self.assertTrue(all('--' in a for a in self.argv()))
        self.assertTrue(any(a[-4:]==['station','wlp2s0','get-networks','rssi-dbms'] for a in self.argv()))

    def test_all_mutations_arguments_and_options(self):
        ssid='-net ; $(touch nope)'
        password="p';$(bad)"
        data, proc=self.invoke({'op':'connect','ssid':ssid,'passphrase':password})
        self.assertTrue(data['ok'],data)
        self.assertNotIn(password,proc.stdout+proc.stderr)
        self.invoke({'op':'disconnect'})
        self.invoke({'op':'radio','enabled':False})
        self.invoke({'op':'forget','ssid':ssid})
        self.invoke({'op':'autoconnect','ssid':ssid,'enabled':False})
        toggle,_=self.invoke({'op':'autoconnect','ssid':'Coffee Shop'})
        self.assertTrue(toggle['ok']); self.assertFalse(toggle['enabled'])
        args=self.argv()
        self.assertIn('--passphrase',args[1]); self.assertIn(password,args[1])
        self.assertTrue(any(a[-4:]==['station','wlp2s0','connect',ssid] for a in args))
        connect=next(a for a in args if a[-4:]==['station','wlp2s0','connect',ssid])
        self.assertLess(connect.index('--'),connect.index(ssid))
        self.assertTrue(any(a[-5:]==['device','wlp2s0','set-property','Powered','off'] for a in args))
        self.assertTrue(any(a[-5:]==['known-networks',ssid,'set-property','AutoConnect','no'] for a in args))
        self.assertTrue(any(a[-3:]==['known-networks',ssid,'forget'] for a in args))

    def test_scan_wait_and_no_hardcoded_adapter(self):
        env=self.env.copy(); env['SCAN_COUNT']=str(self.root/'scan-count')
        out,_=self.invoke({'op':'scan'},env=env)
        self.assertTrue(out['ok'],out)
        self.assertGreaterEqual(int((self.root/'scan-count').read_text()),2)
        self.assertIn(['--dont-ask','--','station','wlp2s0','scan'],self.argv())

    def test_missing_device_and_read_failure_are_errors(self):
        env=self.env.copy(); env['MODE']='bad-devices'
        out,_=self.invoke({'op':'state'},env=env)
        self.assertFalse(out['ok']); self.assertEqual(out['errorKind'],'command')
        env['MODE']='bad-known'
        out,_=self.invoke({'op':'state'},env=env)
        self.assertFalse(out['ok']); self.assertEqual(out['errorKind'],'command')
        env['MODE']='bad-networks'
        out,_=self.invoke({'op':'state'},env=env)
        self.assertFalse(out['ok']); self.assertEqual(out['errorKind'],'command')
        env['MODE']='empty-devices'
        out,_=self.invoke({'op':'scan'},env=env)
        self.assertFalse(out['ok']); self.assertEqual(out['errorKind'],'unavailable')

    def test_auth_generic_and_unavailable_distinction(self):
        env=self.env.copy(); env['MODE']='auth'
        out,_=self.invoke({'op':'forget','ssid':'secret'},env=env)
        self.assertEqual(out['errorKind'],'auth'); self.assertNotIn('secret',out['error'])
        env['MODE']='fail'
        out,_=self.invoke({'op':'forget','ssid':'secret'},env=env)
        self.assertEqual(out['errorKind'],'command')
        env['NETWORK_HELPER_IWCTL']=str(self.root/'missing')
        out,_=self.invoke({'op':'state'},env=env)
        self.assertEqual(out['errorKind'],'unavailable')

    def test_details_route_variants_and_snapshot_contract(self):
        for route, iface, ip, gateway in [
            ('[{"dev":"eth0","src":"192.0.2.4","gateway":"192.0.2.1"}]','eth0','192.0.2.4','192.0.2.1'),
            ('[{"dev":"wlp2s0","prefsrc":"10.0.0.2","gateway":"10.0.0.1"}]','wlp2s0','10.0.0.2','10.0.0.1'),
            ('[{"dev":"tun0","src":"10.8.0.1"}]','tun0','10.8.0.1','')]:
            self.log.write_text('')
            env=self.env.copy(); env['ROUTE']=route
            out,_=self.invoke({'op':'details'},env=env)
            self.assertTrue(out['ok'],out); self.assertEqual((out['info']['iface'],out['info']['ip'],out['info']['gateway']),(iface,ip,gateway))
            args=self.argv(); self.assertEqual(sum(a[:4]==['-j','-4','route','get'] for a in args),1)
            self.assertEqual(sum(a[0]=='-n' for a in args),1)
            self.assertEqual(len(args),2)  # one route lookup + one bound internet ping
            self.assertIn(iface,args[-1]); self.assertEqual((out['info']['rx_bytes'],out['info']['tx_bytes']),(123,456))
        for route in ('[]','[{"dev":"eth0"}]'):
            env=self.env.copy(); env['ROUTE']=route
            out,_=self.invoke({'op':'details'},env=env)
            if route=='[]': self.assertTrue(out['ok']); self.assertEqual(out['info']['iface'],'')
            else: self.assertTrue(out['ok'])

    def test_sample_timestamp_is_taken_before_ping_delay(self):
        env=self.env.copy(); env['PING_DELAY']='.4'
        started=time.monotonic()
        out,_=self.invoke({'op':'details'},env=env)
        ended=time.monotonic()
        self.assertTrue(out['ok'],out)
        self.assertGreater(out['info']['sample_time'],started)
        self.assertLess(out['info']['sample_time'],ended-.35)

    def test_multiple_route_result_uses_first_selected_route(self):
        env=self.env.copy(); env['ROUTE']='[{"dev":"tun0","src":"10.8.0.4"},{"dev":"eth0","src":"192.0.2.2"}]'
        out,_=self.invoke({'op':'details'},env=env)
        self.assertTrue(out['ok'],out); self.assertEqual(out['info']['iface'],'tun0')
        args=self.argv(); self.assertEqual(sum(a[0]=='-n' for a in args),1)
        self.assertIn('tun0',args[-1]); self.assertNotIn('eth0',args[-1])

    def test_leader_exit_does_not_leave_pipe_holding_descendant(self):
        env=self.env.copy(); env.update(MODE='leader-exit',DESC=str(self.marker),ESCAPE='1',NETWORK_HELPER_DEADLINE_SCALE='.02')
        out,_=self.invoke({'op':'state'},env=env,timeout=4)
        self.assertFalse(out['ok']); self.assertEqual(out['errorKind'],'timeout')
        pid=int(self.marker.read_text()); self.assertGone(pid)

    def test_radio_off_skips_station_commands_and_saved_password_omitted(self):
        env=self.env.copy(); env['MODE']='radio-off'
        out,_=self.invoke({'op':'state'},env=env)
        self.assertTrue(out['ok']); self.assertFalse(out['radioOn']); self.assertEqual(out['networks'],[])
        self.assertFalse(any('get-networks' in a or a[-1:] == ['scan'] for a in self.argv()))
        self.log.write_text('')
        out,_=self.invoke({'op':'connect','ssid':'Coffee Shop','passphrase':''})
        self.assertTrue(out['ok']); self.assertNotIn('--passphrase',self.argv()[0])

    def test_ping_tool_error_surfaces_but_packet_loss_is_null(self):
        env=self.env.copy(); env['MODE']='ping-error'
        out,_=self.invoke({'op':'details'},env=env)
        self.assertFalse(out['ok']); self.assertEqual(out['errorKind'],'command')
        env['MODE']='ping-loss'
        out,_=self.invoke({'op':'details'},env=env)
        self.assertTrue(out['ok']); self.assertIsNone(out['info']['internet_ping_ms'])

    def test_malformed_route_and_command_failure_preserve_error(self):
        env=self.env.copy(); env['ROUTE']='not json'
        out,_=self.invoke({'op':'details'},env=env)
        self.assertFalse(out['ok']); self.assertEqual(out['errorKind'],'command')
        env['MODE']='fail'
        out,_=self.invoke({'op':'state'},env=env)
        self.assertFalse(out['ok'])

    def test_fragmented_oversize_and_malformed_input(self):
        p=subprocess.Popen(['python3',str(HELPER)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True,env=self.env)
        p.stdin.write('{"op":'); p.stdin.flush(); time.sleep(.05); p.stdin.write('"state"}'); p.stdin.close()
        out=json.loads(p.stdout.readline()); p.stdout.close(); p.wait(timeout=3); self.assertTrue(out['ok'])
        out,_=self.invoke({},raw='x'*65537); self.assertEqual(out['errorKind'],'malformed')
        out,_=self.invoke({},raw='{bad'); self.assertEqual(out['errorKind'],'malformed')

    def test_timeout_and_cancellation_kills_descendants(self):
        env=self.env.copy(); env.update(MODE='hang',DESC=str(self.marker),ESCAPE='1',NETWORK_HELPER_DEADLINE_SCALE='.02')
        out,_=self.invoke({'op':'state'},timeout=4,env=env)
        self.assertFalse(out['ok']); self.assertEqual(out['errorKind'],'timeout')
        self.assertTrue(self.marker.exists())
        pid=int(self.marker.read_text())
        self.assertGone(pid)


    def test_sigterm_and_sigint_kill_command_group(self):
        for sig in (signal.SIGTERM, signal.SIGINT):
            env=self.env.copy(); env.update(MODE='hang', DESC=str(self.marker))
            p=subprocess.Popen(['python3',str(HELPER)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE,text=True,env=env)
            p.stdin.write(json.dumps({'op':'state'})); p.stdin.close()
            until=time.monotonic()+2
            while not self.marker.exists() and time.monotonic()<until: time.sleep(.01)
            self.assertTrue(self.marker.exists())
            pid=int(self.marker.read_text())
            p.send_signal(sig)
            p.wait(timeout=3)
            p.stdout.close(); p.stderr.close()
            self.assertGone(pid)
            self.marker.unlink()



if __name__ == '__main__':
    unittest.main()
