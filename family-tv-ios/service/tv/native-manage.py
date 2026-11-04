#!/usr/bin/env python3
"""原生客户端初次配置/运维。日常运行不需要电脑、ADB、反向隧道或端口开放。"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import shutil
import time

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = 'org.example.tvchallenge'
COMPONENT = PACKAGE + '/.ControlAccessibilityService'
URI = 'content://' + PACKAGE + '.control/'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('action', choices=['install', 'start', 'observe', 'stop', 'status', 'logs'])
parser.add_argument('--tv', default=os.environ.get('TV_HOST'))
parser.add_argument('--adb', default=os.environ.get('ADB', shutil.which('adb') or str(Path.home() / 'Library/Android/sdk/platform-tools/adb')))
parser.add_argument('--config-file', type=Path, help='后台下载的一次性设备安装凭证JSON')
parser.add_argument('--device', default='Xiaomi_HyperOS_TV')
parser.add_argument('--token-file', type=Path, default=ROOT / 'secrets/device.token')
parser.add_argument('--apk', type=Path, default=ROOT / 'tv/dist/tv-challenge-release.apk')
args = parser.parse_args()
if not args.tv: parser.error('请指定 --tv IP[:端口] 或 TV_HOST')
provision = json.loads(args.config_file.read_text()) if args.config_file else None
if provision:
    if not isinstance(provision, dict) or not isinstance(provision.get('device'), str) or not isinstance(provision.get('token'), str):
        parser.error('设备安装凭证格式错误')
    args.device = provision['device']
serial = args.tv if ':' in args.tv else args.tv + ':5555'

def adb(*words, data=None):
    result = subprocess.run([args.adb, '-s', serial, *words], input=data, capture_output=True, check=True)
    output = result.stdout.decode(errors='replace')
    if 'SecurityException' in output or 'Permission Denial' in output or 'Error while accessing' in output:
        raise RuntimeError('电视拒绝运维权限；请检查调试授权。')
    return output.strip()

def services():
    value = adb('shell', 'settings', 'get', 'secure', 'enabled_accessibility_services')
    return [] if value in ('', 'null') else value.split(':')

def ours(value):
    return value in (COMPONENT, PACKAGE + '/' + PACKAGE + '.ControlAccessibilityService')

def configure_services(enable):
    entries = [x for x in services() if not ours(x)]
    if enable:
        entries.append(COMPONENT)
    adb('shell', 'settings', 'put', 'secure', 'enabled_accessibility_services', ':'.join(entries))
    adb('shell', 'settings', 'put', 'secure', 'accessibility_enabled', '1' if entries else '0')

try:
    connected = subprocess.run([args.adb, 'connect', serial], capture_output=True)
    state = subprocess.run([args.adb, '-s', serial, 'get-state'], capture_output=True, text=True)
    ready = connected.returncode == 0 and state.returncode == 0 and state.stdout.strip() == 'device'
except FileNotFoundError:
    ready = False
if not ready:
    # 不调试macOS隐私拦截；直接使用项目内的Python ADB客户端。
    args.adb = str(ROOT / 'tv/native-adb.py')
    subprocess.run([args.adb, 'connect', serial], capture_output=True, check=True)
if adb('get-state') != 'device':
    raise SystemExit('初次配置需要在电视开启ADB并允许授权。完成后可以关闭ADB。')
if args.action in ('status', 'logs'):
    print(adb('shell', 'content', 'query' if args.action == 'status' else 'read', '--uri', URI + ('status' if args.action == 'status' else 'events')))
    raise SystemExit(0)
if args.action == 'stop':
    adb('shell', 'content', 'write', '--uri', URI + 'config', data=b'{"enabled":false}')
    time.sleep(1)
    configure_services(False)
    print('已停用原生管控并取消恢复任务；保留凭证、观看数据和客户端安装。')
    raise SystemExit(0)
if args.action == 'install':
    installed = adb('install', '-r', str(args.apk))
    if 'Success' not in installed: raise RuntimeError('APK未确认安装成功，请检查电视提示；未继续交付配置。')
    print('APK覆盖安装成功')
sdk = int(adb('shell', 'getprop', 'ro.build.version.sdk'))
permissions = ['DUMP', 'WRITE_SECURE_SETTINGS'] + (['POST_NOTIFICATIONS'] if sdk >= 33 else [])
for permission in permissions:
    adb('shell', 'pm', 'grant', PACKAGE, 'android.permission.' + permission)
ops = ['RUN_IN_BACKGROUND', 'RUN_ANY_IN_BACKGROUND'] + (['SCHEDULE_EXACT_ALARM'] if sdk >= 31 else [])
for op in ops:
    adb('shell', 'cmd', 'appops', 'set', PACKAGE, op, 'allow')
adb('shell', 'dumpsys', 'deviceidle', 'whitelist', '+' + PACKAGE)
configure_services(True)
body = {'origin': provision['origin'] if provision else 'https://familytv-api.princewck.workers.dev', 'device': args.device, 'token': provision['token'] if provision else args.token_file.read_text().strip(), 'enabled': True, 'mode': 'observe' if args.action in ('install', 'observe') else 'enforce'}
# 令牌经stdin和Binder管道直接写入应用私有存储，绝不写入命令行、URL或日志。
adb('shell', 'content', 'write', '--uri', URI + 'config', data=json.dumps(body).encode())
time.sleep(2)
print(adb('shell', 'content', 'query', '--uri', URI + 'status'))
print('配置已交付电视；请以后台新心跳、实际播放和重启验收确认，不以配置命令成功代替功能验收。')
