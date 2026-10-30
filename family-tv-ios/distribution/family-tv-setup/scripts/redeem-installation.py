#!/usr/bin/env python3
"""Redeem the short-lived code from the parent's screenshot; never print tokens."""
import argparse, json, os, re, ssl, sys, urllib.request, urllib.parse
from pathlib import Path
class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ValueError('Service redirect refused')
def main():
    p = argparse.ArgumentParser()
    p.add_argument('--origin', required=True)
    p.add_argument('--code', required=True)
    p.add_argument('--device', required=True)
    p.add_argument('--output', default='secrets/device-provision.json')
    a=p.parse_args()
    u=urllib.parse.urlsplit(a.origin)
    if u.scheme!='https' or not u.hostname or u.username or u.password or u.path not in ('','/') or u.query or u.fragment:
        raise ValueError('An HTTPS service origin is required')
    if a.origin.rstrip('/') not in ['https://familytv-api.princewck.workers.dev','https://tv.chengkai.wang']:
        raise ValueError('Unsupported service origin')
    code=re.sub(r'[-\s]','',a.code).upper()
    if not re.fullmatch('[0-9A-F]{16}',code):raise ValueError('Invalid installation code')
    out=Path(a.output)
    if out.exists():raise ValueError('Output exists; use the existing private file or choose a new path')
    out.parent.mkdir(parents=True,exist_ok=True,mode=0o700)
    opener=urllib.request.build_opener(NoRedirect(),urllib.request.HTTPSHandler(context=ssl.create_default_context()))
    req=urllib.request.Request(a.origin.rstrip('/')+'/installation/redeem',data=json.dumps({'code':code}).encode(),headers={'Content-Type':'application/json','Accept':'application/json'},method='POST')
    with opener.open(req,timeout=20) as response:
        data=json.loads(response.read(16385))
    if data.get('device')!=a.device or data.get('origin')!=a.origin.rstrip('/') or not re.fullmatch(r'[A-Za-z0-9_-]{1,64}',data.get('device','')) or not re.fullmatch(r'[A-Za-z0-9_-]{43}',data.get('token','')):
        raise ValueError('Incompatible service response')
    fd=os.open(out,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    with os.fdopen(fd,'w') as f:json.dump(data,f)
    print('Installation credentials saved privately. Continue with references/install.md and phone health checks.')
if __name__=='__main__':
    try:main()
    except Exception as e:
        print('Installation code could not be redeemed: '+type(e).__name__+'. Check the service, expiry and private output file.',file=sys.stderr)
        sys.exit(1)
