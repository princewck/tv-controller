#!/usr/bin/env python3
"""检查当前 Git 跟踪文件；额外的私有敏感值由本地发布流程检查，不写入此脚本。"""
from pathlib import Path
import hashlib, re, subprocess, sys
root=Path(__file__).resolve().parents[1]
files=subprocess.check_output(['git','ls-files','-z'],cwd=root).decode().split('\0')
errors=[]
patterns=[r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',r'gh[pousr]_[A-Za-z0-9]{30,}',r'github_pat_[A-Za-z0-9_]{40,}',r'AKIA[0-9A-Z]{16}',r'LTAI[A-Za-z0-9]{12,}',r'(?<![0-9])192\.168\.\d{1,3}\.\d{1,3}']
for name in filter(None,files):
 p=root/name
 if any(x in Path(name).parts for x in ['secrets','work','node_modules','.gradle','home-entry']) or p.suffix in ['.apk','.dex','.sqlite','.jks','.keystore','.pem','.key']:
  errors.append(name+': forbidden artifact');continue
 raw=p.read_bytes()
 try: text=raw.decode('utf-8')
 except UnicodeDecodeError:
  if p.suffix=='.png' and raw.startswith(b'\x89PNG\r\n\x1a\n'): continue
  if p.name=='AppleRootCA-G3.cer' and hashlib.sha256(raw).hexdigest()=='63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179': continue
  errors.append(name+': unexpected binary artifact');continue
 if any(re.search(pattern,text) for pattern in patterns): errors.append(name+': credential or device address pattern')
 if re.search(r'/(?:Users|home)/[A-Za-z0-9_-]+/',text): errors.append(name+': private home path')
if errors:
 print('\n'.join(errors));sys.exit(1)
print(f'已检查 {len(list(filter(None,files)))} 个跟踪文件，未发现禁用产物或常见敏感模式。')
