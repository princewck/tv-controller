#!/usr/bin/env python3
"""首次部署前，将安全示例域名同时替换到 Android、API、网页和 Nginx。"""
import argparse
from pathlib import Path
import re
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('domain', help='例如 tv.your-domain.com；不含 https:// 或路径')
args = parser.parse_args()
if not re.fullmatch(r'(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}', args.domain):
    parser.error('请填写小写公网域名')
if args.domain == 'tv.example.com': parser.error('示例域名不能用于真实部署')
root = Path(__file__).resolve().parents[1]
# 仅替换已审阅的模板路径，不读取运行目录、凭证、Git、依赖和本脚本。
files = [root / '.env.example']
for directory in ['server', 'public', 'deploy', 'android-webview/app/src', 'test']:
    files.extend(x for x in (root / directory).rglob('*') if x.is_file() and 'build' not in x.relative_to(root / directory).parts)
count = 0
for file in files:
    text = file.read_text()
    changed = text.replace('tv.example.com', args.domain).replace(r'tv\\.example\\.com', args.domain.replace('.', r'\\.'))
    if changed != text: file.write_text(changed); count += 1
if not count: parser.error('未找到模板；本脚本仅用于干净模板的首次配置，修改已有域名请手动审核')
print(f'已配置 {count} 个文件；请重新构建 APK、运行测试并生成 Nginx 配置。')
