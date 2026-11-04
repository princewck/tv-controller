"""Validate reviewed whole-sentence translations and export Apple .strings files.

Usage: python3 scripts/build-localizations.py reviewed-translations.json
The input is an array of {key, zh-Hans, en, ko, ja} objects.
"""
import json
from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parents[1]
rows = json.loads(Path(sys.argv[1]).read_text())
assert len({row['key'] for row in rows}) == len(rows), 'Duplicate localization keys'
tokens = lambda value: sorted(re.findall(r'\{p[0-9]+\}', value))
quote = lambda value: json.dumps(value, ensure_ascii=False)
permission = {
    'zh-Hans': '用于发现并加密连接你配对的家庭电视，直接发送暂停、额度和观看规则。拒绝后仍可使用云端。',
    'en': 'Find and securely connect to your paired household TVs to send pause commands, viewing time and rules directly. Cloud controls remain available if you decline.',
    'ko': '페어링한 가족 TV를 찾아 암호화된 연결로 일시정지, 시청 시간과 규칙을 직접 전송합니다. 허용하지 않아도 클라우드 제어는 사용할 수 있습니다.',
    'ja': 'ペアリングした家庭のテレビを検出し、暗号化接続で一時停止、視聴時間、ルールを直接送信します。許可しなくてもクラウド経由で操作できます。',
}
for language in permission:
    for row in rows:
        assert row[language].strip(), (language, row['key'])
        assert tokens(row['key']) == tokens(row[language]), (language, row['key'], 'placeholder mismatch')
    directory = root / 'Resources' / (language + '.lproj')
    directory.mkdir(exist_ok=True)
    directory.joinpath('Localizable.strings').write_text('// Reviewed whole-sentence app copy. Runtime values remain unchanged.\n' + '\n'.join(
        f'{quote(row["key"])} = {quote(row[language])};' for row in sorted(rows, key=lambda row: row['key'])
    ) + '\n')
    directory.joinpath('InfoPlist.strings').write_text(
        f'"CFBundleDisplayName" = {quote("观有度" if language == "zh-Hans" else "Family TV")};\n'
        f'"NSLocalNetworkUsageDescription" = {quote(permission[language])};\n'
    )
print(f'Validated and exported {len(rows)} keys in {len(permission)} languages.')
