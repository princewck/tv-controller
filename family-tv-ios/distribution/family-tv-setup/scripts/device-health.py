#!/usr/bin/env python3
"""Read only this TV's cloud diagnostics without printing its device token."""
import argparse,json,ssl,urllib.request,sys
from pathlib import Path
class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,*args):raise ValueError('Redirect refused')
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--config-file',type=Path,required=True);p.add_argument('--require-ready',action='store_true');p.add_argument('--require-complete',action='store_true');a=p.parse_args()
    config=json.loads(a.config_file.read_text());origin=config['origin']
    if origin not in ['https://familytv-api.princewck.workers.dev','https://tv.chengkai.wang']:raise ValueError('Unsupported origin')
    opener=urllib.request.build_opener(NoRedirect(),urllib.request.HTTPSHandler(context=ssl.create_default_context()))
    req=urllib.request.Request(origin+'/device/status',headers={'User-Agent':'FamilyTV-Setup/1.0.2','Authorization':'Bearer '+config['token'],'Accept':'application/json'})
    with opener.open(req,timeout=20) as response:
        data=json.loads(response.read(32769))
    if data.get('device')!=config['device'] or data.get('protocol_version')!=2 or data.get('state',{}).get('mode')!='daily':raise ValueError('Incompatible device protocol')
    keys=['device','protocol_version','last_heartbeat_ms','permissions_ok','boot_count','adb_enabled']
    value={k:data.get(k) for k in keys};state=data['state'];value['state']={k:state.get(k) for k in ['mode','status','control_revision','applied_revision','enforcement_result','applied_ms','watched_seconds','server_now_ms']}
    value['policy_snapshot_available']=isinstance(state.get('policy_snapshot'),dict)
    value['checks']=data.get('checks',{});value['complete']=data.get('complete') is True
    import time
    heartbeat=data.get('last_heartbeat_ms');ready=isinstance(heartbeat,(float,int)) and -5000<=time.time()*1000-heartbeat<45000 and data.get('permissions_ok') is True and state.get('applied_revision')==state.get('control_revision') and isinstance(state.get('control_revision'),int) and state.get('enforcement_result') in ['observing','allowed','stopped'] and value['policy_snapshot_available']
    value['ready']=ready
    print(json.dumps(value,ensure_ascii=False,indent=2))
    if (a.require_ready and not ready) or (a.require_complete and not (ready and value['complete'] and all(value['checks'].get(k) is True for k in ['connected','playback_test','permissions','adb_closed','rebooted']))):sys.exit(2)
if __name__=='__main__':
    try:main()
    except Exception as e:print('Device health unavailable: '+type(e).__name__+'. Check service and this TV configuration.',file=sys.stderr);sys.exit(1)
