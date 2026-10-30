#!/usr/bin/env python3
"""Configure the TV with the official Android SDK adb; never claim hardware acceptance."""
import argparse,hashlib,ipaddress,json,os,re,shutil,subprocess,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
PACKAGE='org.example.tvchallenge';COMPONENT=PACKAGE+'/.ControlAccessibilityService';URI='content://'+PACKAGE+'.control/'
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('action',choices=['install','start','observe','stop','status','logs'])
p.add_argument('--tv',required=True,help='TV IP:connection-port; not its TLS pairing port')
p.add_argument('--adb',default=shutil.which('adb') or str(Path.home()/'Library/Android/sdk/platform-tools/adb'))
p.add_argument('--config-file',type=Path)
p.add_argument('--expect-origin',help='Exact HTTPS origin from this screenshot')
p.add_argument('--expect-device',help='Exact device ID from this screenshot')
p.add_argument('--apk',type=Path)
a=p.parse_args();manifest=json.loads((ROOT/'assets/release.json').read_text());allowed=['https://familytv-api.princewck.workers.dev','https://tv.chengkai.wang']
try:
    parts=a.tv.rsplit(':',1);host=parts[0];port=int(parts[1]) if len(parts)==2 else 5555
    ipaddress.IPv4Address(host)
    if not 1<=port<=65535:raise ValueError()
except ValueError:p.error('--tv must be an IPv4 address with its connection port')
serial=f'{host}:{port}';config=None
if a.action in ['install','start','observe']:
    if not a.config_file or not a.expect_origin or not a.expect_device:p.error('Provide --config-file, --expect-origin and --expect-device from this screenshot')
    if a.config_file.stat().st_mode&0o077:p.error('Credential file must be private (chmod 600)')
    config=json.loads(a.config_file.read_text())
    if a.expect_origin not in allowed or config.get('origin')!=a.expect_origin or config.get('device')!=a.expect_device or not re.fullmatch(r'[A-Za-z0-9_-]{32,128}',config.get('token','')):p.error('Credential origin/device does not match this screenshot')
if a.action=='install':
    if not a.apk or hashlib.sha256(a.apk.read_bytes()).hexdigest()!=manifest['apk']['sha256']:p.error('Use the APK verified against this release manifest')
def adb(*words,data=None):
    r=subprocess.run([a.adb,'-s',serial,*words],input=data,capture_output=True,check=True,timeout=20)
    out=r.stdout.decode(errors='replace')
    if any(x in out for x in ['SecurityException','Permission Denial','Error while accessing','Unknown operation']):raise RuntimeError('TV rejected the operation')
    return out.strip()
def status():
    out=adb('shell','content','query','--uri',URI+'status');start=out.find('{');end=out.rfind('}')
    if start<0 or end<start:raise RuntimeError('TV status is missing')
    return json.loads(out[start:end+1])
def services(enable):
    old=adb('shell','settings','get','secure','enabled_accessibility_services')
    values=[] if old in ['','null'] else old.split(':')
    values=[x for x in values if x not in [COMPONENT,PACKAGE+'/'+PACKAGE+'.ControlAccessibilityService']]
    if enable:values.append(COMPONENT)
    adb('shell','settings','put','secure','enabled_accessibility_services',':'.join(values))
    adb('shell','settings','put','secure','accessibility_enabled','1' if values else '0')
try:
    subprocess.run([a.adb,'connect',serial],capture_output=True,check=True,timeout=20)
    if adb('get-state')!='device':raise RuntimeError('Confirm the debugging authorization on this TV')
    if a.action=='logs':print(adb('shell','content','read','--uri',URI+'events'));raise SystemExit(0)
    if a.action=='status':print(json.dumps(status(),ensure_ascii=False,indent=2));raise SystemExit(0)
    sdk=int(adb('shell','getprop','ro.build.version.sdk'))
    if sdk<26:raise RuntimeError('Android 8.0 or later is required; no configuration changed')
    if a.action=='stop':
        adb('shell','content','write','--uri',URI+'config',data=b'{"enabled":false}');time.sleep(1);services(False)
        if status().get('enabled') is not False:raise RuntimeError('TV did not confirm disabled state')
        print('Monitoring disabled; client and private credentials preserved.');raise SystemExit(0)
    if a.action=='install':
        if 'Success' not in adb('install','-r',str(a.apk)):raise RuntimeError('APK installation not confirmed; preserve existing installation on signing conflict')
    permissions=['DUMP','WRITE_SECURE_SETTINGS']+(['POST_NOTIFICATIONS'] if sdk>=33 else [])
    for permission in permissions:adb('shell','pm','grant',PACKAGE,'android.permission.'+permission)
    for op in ['RUN_IN_BACKGROUND','RUN_ANY_IN_BACKGROUND']+(['SCHEDULE_EXACT_ALARM'] if sdk>=31 else []):adb('shell','cmd','appops','set',PACKAGE,op,'allow')
    adb('shell','dumpsys','deviceidle','whitelist','+'+PACKAGE);services(True)
    mode='enforce' if a.action=='start' else 'observe'
    body={k:config[k] for k in ['origin','device','token']};body.update(enabled=True,mode=mode)
    previous_heartbeat=status().get('last_heartbeat_ms',0)
    configured_ms=time.time()*1000
    adb('shell','content','write','--uri',URI+'config',data=json.dumps(body).encode())
    deadline=time.monotonic()+25
    while True:
        value=status();fresh=isinstance(value.get('last_heartbeat_ms'),(int,float)) and value['last_heartbeat_ms']>previous_heartbeat and value['last_heartbeat_ms']>=configured_ms-5000 and -5000<=time.time()*1000-value['last_heartbeat_ms']<45000
        ready=value.get('origin')==a.expect_origin and value.get('device')==a.expect_device and value.get('mode')==mode and all(value.get(k) is True for k in ['enabled','native_service_running','accessibility_bound','dump_granted']) and fresh
        if ready:break
        if time.monotonic()>=deadline:raise RuntimeError('Configuration sent but TV status/permissions/new heartbeat not confirmed; do not complete setup')
        time.sleep(2)
    print(json.dumps(value,ensure_ascii=False,indent=2));print('Configuration and current heartbeat confirmed. Real playback, phone checks, ADB closure and full reboot still required by SKILL.md.')
except (OSError,ValueError,RuntimeError,subprocess.SubprocessError) as e:
    print('TV configuration incomplete: '+type(e).__name__+'. Verify this TV, official adb authorization, protocol and required permissions. Do not claim acceptance.',file=__import__('sys').stderr);raise SystemExit(1)
