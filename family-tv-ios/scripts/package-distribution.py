#!/usr/bin/env python3
"""Package immutable version URLs. Existing different bytes require a new version."""
import hashlib,json,shutil,zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
SKILL=ROOT/'distribution/family-tv-setup'
PUBLIC=ROOT/'cloud/public'
ORIGIN='https://familytv-api.princewck.workers.dev'
def sha(data):return hashlib.sha256(data).hexdigest()
def immutable(path,data):
    path.parent.mkdir(parents=True,exist_ok=True)
    if path.exists() and path.read_bytes()!=data:raise RuntimeError('Version already packaged with different bytes: '+str(path)+'; bump the release version')
    if not path.exists():path.write_bytes(data)
def main():
    manifest=json.loads((SKILL/'assets/release.json').read_text());apk=manifest['apk']
    data=(ROOT/'service/android-webview/app/build/outputs/apk/release/app-release.apk').read_bytes()
    if sha(data)!=apk['sha256'] or len(data)!=apk['size']:raise RuntimeError('APK differs from the reviewed release manifest')
    immutable(PUBLIC/('downloads/tv/'+apk['version']+'/family-tv.apk'),data)
    import io
    out=io.BytesIO()
    with zipfile.ZipFile(out,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as archive:
        for file in sorted(SKILL.rglob('*')):
            if not file.is_file() or '__pycache__' in file.parts:continue
            if file.is_symlink():raise RuntimeError('Symlink in skill package')
            if file.suffix not in ['.md','.py','.json','.yaml','.txt']:raise RuntimeError('Unexpected skill resource: '+str(file))
            name='family-tv-setup/'+file.relative_to(SKILL).as_posix()
            info=zipfile.ZipInfo(name,date_time=(2026,1,1,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED
            info.external_attr=(0o100755 if file.suffix=='.py' else 0o100644)<<16
            archive.writestr(info,file.read_bytes())
    skill_data=out.getvalue();prefix='downloads/install/'+manifest['skill_version']
    immutable(PUBLIC/(prefix+'/family-tv-setup.zip'),skill_data)
    release={**manifest,'skill':{'url':ORIGIN+'/'+prefix+'/family-tv-setup.zip','sha256':sha(skill_data),'size':len(skill_data)}}
    immutable(PUBLIC/(prefix+'/manifest.json'),(json.dumps(release,ensure_ascii=False,indent=2)+'\n').encode())
    print(json.dumps({'apk':apk['url'],'skill':release['skill']['url'],'skill_sha256':sha(skill_data),'files':len(zipfile.ZipFile(io.BytesIO(skill_data)).namelist())},indent=2))
if __name__=='__main__':main()
