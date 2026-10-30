#!/usr/bin/env python3
"""Download only this skill release's APK, verify its hash, and never overwrite."""
import argparse, hashlib, json, os, ssl, tempfile, urllib.parse, urllib.request
from pathlib import Path
class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ValueError('Download redirect refused')
def download(manifest, output):
    apk=manifest['apk'];url=urllib.parse.urlsplit(apk['url'])
    if url.scheme!='https' or url.hostname!='familytv-api.princewck.workers.dev' or url.username or url.password or url.query or url.fragment or url.path!=f"/downloads/tv/{apk['version']}/family-tv.apk":
        raise ValueError('Unexpected versioned APK URL')
    if output.exists():
        if hashlib.sha256(output.read_bytes()).hexdigest()==apk['sha256']:
            print('Existing APK matches the release SHA-256.');return
        raise ValueError('Output exists with different contents; choose another path')
    output.parent.mkdir(parents=True,exist_ok=True)
    opener=urllib.request.build_opener(NoRedirect(),urllib.request.HTTPSHandler(context=ssl.create_default_context()))
    temporary=None
    try:
        with opener.open(urllib.request.Request(apk['url'],headers={'Accept':'application/vnd.android.package-archive'}),timeout=30) as response, tempfile.NamedTemporaryFile(dir=output.parent,delete=False) as file:
            temporary=Path(file.name);digest=hashlib.sha256();size=0
            while True:
                data=response.read(65536)
                if not data:break
                size+=len(data)
                if size>25*1024*1024:raise ValueError('APK exceeds release limit')
                digest.update(data);file.write(data)
        if size!=apk['size'] or digest.hexdigest()!=apk['sha256']:raise ValueError('APK checksum or size mismatch')
        os.link(temporary,output)
        print('Version '+apk['version']+' APK downloaded; SHA-256 verified.')
    finally:
        if temporary:temporary.unlink(missing_ok=True)
def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output',type=Path,required=True);args=parser.parse_args()
    manifest=json.loads((Path(__file__).resolve().parents[1]/'assets/release.json').read_text())
    download(manifest,args.output)
if __name__=='__main__':main()
