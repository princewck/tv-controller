#!/usr/bin/env python3
"""Regression tests: release drift must block rather than silently fix itself."""
import importlib.util
import json
import shutil
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('gate', Path(__file__).with_name('check-distribution.py'))
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)


class DistributionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        for folder in ['distribution', 'Core', 'Resources', 'cloud/public/downloads']:
            shutil.copytree(gate.ROOT / folder, self.root / folder)
        (self.root / 'scripts').mkdir()
        shutil.copyfile(gate.ROOT / 'scripts/distribution-inputs.xcfilelist', self.root / 'scripts/distribution-inputs.xcfilelist')
        self.release = json.loads((self.root / 'distribution/downloads.json').read_text())
        self.version = self.release['skill_version']
        file = Path('service/android-webview/app/build.gradle')
        (self.root / file).parent.mkdir(parents=True)
        shutil.copyfile(gate.ROOT / file, self.root / file)

    def replace(self, relative, old, new):
        p = self.root / relative
        p.write_text(p.read_text().replace(old, new))

    def test_current_release_passes(self):
        self.assertEqual(gate.check(self.root), self.version)

    def test_new_apk_version_with_old_url_fails(self):
        self.replace('service/android-webview/app/build.gradle', f"versionName '{self.release['apk']['version']}'", "versionName '999.0.0'")
        with self.assertRaisesRegex(ValueError, 'versionName'):
            gate.check(self.root)

    def test_stale_generated_app_url_fails(self):
        self.replace('Core/ReleaseDownloads.swift', f'/{self.version}/', '/0.0.0/')
        with self.assertRaisesRegex(ValueError, 'App download URL is stale'):
            gate.check(self.root)

    def test_domain_typo_fails(self):
        p = self.root / f'cloud/public/downloads/install/{self.version}/manifest.json'
        p.write_text(p.read_text().replace('princewck', 'princewcwk'))
        with self.assertRaises(ValueError):
            gate.check(self.root)

    def test_changed_skill_without_repackaging_fails(self):
        p = self.root / 'distribution/family-tv-setup/SKILL.md'
        p.write_text(p.read_text() + '\nUpdated instructions\n')
        with self.assertRaisesRegex(ValueError, 'Installer source changed'):
            gate.check(self.root)

    def test_corrupted_artifact_fails(self):
        p = self.root / f"cloud/public/downloads/tv/{self.release['apk']['version']}/family-tv.apk"
        p.write_bytes(b'not the released APK')
        with self.assertRaisesRegex(ValueError, 'size mismatch'):
            gate.check(self.root)

    def test_hardcoded_translation_fails(self):
        p = self.root / 'Resources/en.lproj/Localizable.strings'
        p.write_text(p.read_text() + '\n"bad" = "https://wrong.example/downloads/install/old.zip";\n')
        with self.assertRaisesRegex(ValueError, 'Hardcoded installer URL'):
            gate.check(self.root)


if __name__ == '__main__':
    unittest.main()
