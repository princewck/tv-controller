#!/usr/bin/env python3
"""供native-manage使用的最小ADB适配器，解决macOS对独立adb二进制的局域网访问限制。
使用开源adb-shell认证客户端；文件经受限目录内的base64小块传输并校验MD5。
只支持本项目使用的connect/get-state/shell/install操作，不修改系统adb或网络配置。
"""
import base64
import hashlib
import os
from pathlib import Path
import shlex
import sys
import uuid

try:
    from adb_shell.adb_device import AdbDeviceTcp
    from adb_shell.auth.keygen import keygen
    from adb_shell.auth.sign_pythonrsa import PythonRSASigner
except ImportError:
    raise SystemExit('请在虚拟环境运行 pip install -r tv/requirements.txt，再从该环境调用 native-manage.py')

args = sys.argv[1:]
serial = os.environ.get('TV_HOST', '')
if args[:1] == ['-s']:
    serial, args = args[1], args[2:]
if args[:1] == ['connect']:
    serial = args[1]
if not args:
    raise SystemExit('需要connect/get-state/shell/install')
if ':' not in serial:
    raise SystemExit('需要 IPv4:端口；此适配器仅用于受信任局域网的明文 ADB，不支持无线调试 TLS 配对端口')
host, port = serial.rsplit(':', 1)
if not host or not port.isdigit() or not 1 <= int(port) <= 65535:
    raise SystemExit('ADB 地址无效')
# 默认使用用户现有 ADB 密钥；新密钥仅存用户私有配置目录，不进入项目。
key = Path(os.environ.get('TV_ADB_KEY', str(Path.home() / '.android/adbkey')))
if not key.exists():
    key.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    old = os.umask(0o077)
    try: keygen(str(key))
    finally: os.umask(old)
signer = PythonRSASigner(key.with_suffix(key.suffix + '.pub').read_text(), key.read_text())
dev = AdbDeviceTcp(host, int(port), default_transport_timeout_s=15)
dev.connect(rsa_keys=[signer], transport_timeout_s=15, auth_timeout_s=60)
base = '/data/local/tmp/tv-parent-control'

def shell(command):
    marker = '__TV_NATIVE_EXIT__'
    result = dev.shell(command + '; _tv_native_rc=$?; echo "' + marker + '$_tv_native_rc"', read_timeout_s=90)
    output, sep, code = result.rpartition(marker)
    if not sep:
        raise RuntimeError('电视没有返回完整命令状态')
    return output, int(code.strip())

def upload(data, remote):
    for cmd in ('mkdir -p ' + base, 'chmod 700 ' + base, 'umask 077; : > ' + shlex.quote(remote + '.b64')):
        if shell(cmd)[1]:
            raise RuntimeError('无法准备私有传输目录')
    encoded = base64.b64encode(data).decode('ascii')
    for offset in range(0, len(encoded), 1536):
        if shell("printf '%s' '" + encoded[offset:offset+1536] + "' >> " + shlex.quote(remote + '.b64'))[1]:
            raise RuntimeError('文件传输失败，未执行安装/配置')
    if shell('base64 -d < ' + shlex.quote(remote + '.b64') + ' > ' + shlex.quote(remote))[1]:
        raise RuntimeError('文件解码失败')
    shell('chmod 600 ' + shlex.quote(remote))
    digest, code = shell('md5sum ' + shlex.quote(remote))
    if code or digest.split()[0] != hashlib.md5(data).hexdigest():
        raise RuntimeError('文件校验失败')
    shell('rm ' + shlex.quote(remote + '.b64'))

try:
    operation = args[0]
    if operation == 'connect':
        print('connected to ' + serial)
    elif operation == 'get-state':
        print('device')
    elif operation == 'shell':
        words = args[1:]
        command = shlex.join(words)
        remote = None
        if words[:2] == ['content', 'write']:
            data = sys.stdin.buffer.read(8193)
            if len(data) > 8192:
                raise RuntimeError('配置超过长度限制')
            remote = base + '/private-config-' + uuid.uuid4().hex + '.json'
            upload(data, remote)
            command += ' < ' + shlex.quote(remote)
        try:
            out, code = shell(command)
            sys.stdout.write(out)
        finally:
            if remote:
                shell('rm ' + shlex.quote(remote))
        if code:
            raise SystemExit(code)
    elif operation == 'install' and len(args) == 3 and args[1] == '-r':
        remote = base + '/update-' + uuid.uuid4().hex + '.apk'
        upload(Path(args[2]).read_bytes(), remote)
        try:
            out, code = shell('pm install -r ' + shlex.quote(remote))
            sys.stdout.write(out)
            if code or 'Success' not in out:
                raise SystemExit(code or 1)
        finally:
            shell('rm ' + shlex.quote(remote))
    else:
        raise SystemExit('本适配器不支持该操作')
finally:
    dev.close()
