"""Verify release APK metadata, signatures, ZIP integrity and 16 KB alignment."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import zipfile

class AndroidTools:
    """Resolve SDK tools without leaking Windows defaults into Linux CI."""

    def __init__(self, build_tools_version='35.0.0', *, environment=None, windows=None):
        self.windows = os.name == 'nt' if windows is None else windows
        self.environment = dict(os.environ if environment is None else environment)
        sdk = self.environment.get('ANDROID_HOME') or self.environment.get('ANDROID_SDK_ROOT')
        if not sdk and self.windows:
            sdk = 'D:/Codex-Migrated/Android/Sdk'
        if not sdk:
            raise RuntimeError('Set ANDROID_HOME or ANDROID_SDK_ROOT to the Android SDK directory.')
        self.build_tools = Path(sdk) / 'build-tools' / build_tools_version

        # Keep the original local Windows fallback; Linux can use Java on PATH.
        if self.windows:
            self.environment.setdefault('JAVA_HOME', r'D:\CodexToolchains\jdk17\jdk-17.0.16+8')
        java_home = self.environment.get('JAVA_HOME')
        if java_home:
            self.environment['PATH'] = (str(Path(java_home) / 'bin') + os.pathsep
                                        + self.environment.get('PATH', ''))

    def run(self, tool, *params):
        suffix = ('.bat' if tool == 'apksigner' else '.exe') if self.windows else ''
        result = subprocess.run([str(self.build_tools / (tool + suffix)), *map(str, params)],
                                capture_output=True, text=True, encoding='utf-8', errors='replace',
                                env=self.environment)
        if result.returncode:
            raise RuntimeError(result.stdout + result.stderr)
        return result.stdout


def verify_apks(root, version, build_number, tools):
    reports = []
    expected_certificates = None
    for abi, code, machine in [('arm64-v8a', 2000, 183), ('x86_64', 4000, 62)]:
        apk = root / f'build/app/outputs/flutter-apk/app-{abi}-release.apk'
        badging = tools.run('aapt', 'dump', 'badging', apk)
        assert f"versionName='{version}'" in badging
        assert f"versionCode='{code + build_number}'" in badging
        assert "name='io.github.metammy07.novels'" in badging
        assert "application-label:'LiteTale'" in badging
        manifest = tools.run('aapt', 'dump', 'xmltree', apk, 'AndroidManifest.xml')
        assert 'enableOnBackInvokedCallback' not in manifest, 'Experimental back opt-in must be removed'
        signature = tools.run('apksigner', 'verify', '--verbose', '--print-certs', apk)
        # Compare every APK signer, excluding optional source-stamp certificates.
        certificate_lines = [line for line in signature.splitlines()
                             if line.startswith('Signer #') and 'certificate SHA-256 digest:' in line]
        assert certificate_lines, f'APK signer certificate missing: {abi}'
        certificates = sorted(line.split('certificate SHA-256 digest:', 1)[1].strip().lower()
                              for line in certificate_lines)
        if expected_certificates is None:
            expected_certificates = certificates
        assert certificates == expected_certificates, 'APK signing certificates differ between ABIs'
        tools.run('zipalign', '-c', '-P', '16', '4', apk)
        with zipfile.ZipFile(apk) as archive:
            assert archive.testzip() is None
            libraries = [n for n in archive.namelist() if n.startswith('lib/') and n.endswith('.so')]
            assert all(f'lib/{abi}/{name}' in libraries for name in
                       ['libapp.so', 'libflutter.so', 'librust_lib_wild.so', 'libc++_shared.so'])
            for name in libraries:
                data = archive.read(name)
                assert data[:6] == b'\x7fELF\x02\x01'
                assert struct.unpack_from('<H', data, 18)[0] == machine
                phoff = struct.unpack_from('<Q', data, 32)[0]
                entsize, count = struct.unpack_from('<HH', data, 54)
                for i in range(count):
                    offset = phoff + i * entsize
                    if struct.unpack_from('<I', data, offset)[0] == 1:
                        assert struct.unpack_from('<Q', data, offset + 48)[0] >= 16384, name
        reports.append({'abi': abi, 'version': version, 'versionCode': code + build_number,
                        'sha256': hashlib.sha256(apk.read_bytes()).hexdigest(),
                        'bytes': apk.stat().st_size, 'experimentalPredictiveBack': False,
                        'zipIntegrity': 'passed', 'alignment16KB': 'passed',
                        'certificate': certificate_lines[0]})
    return reports


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument('--version', default='1.0.0')
    parser.add_argument('--build-number', type=int, default=73)
    parser.add_argument('--build-tools-version', default='35.0.0')
    parser.add_argument('--report', type=Path, help='Optional release-specific JSON report path')
    args = parser.parse_args(argv)
    root = Path(__file__).resolve().parents[1]
    reports = verify_apks(root, args.version, args.build_number,
                          AndroidTools(args.build_tools_version))
    output = (root / args.report if args.report else
              root / f'build/reader-curl/{args.version}-apk-verification.json')
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(reports, indent=2), encoding='utf-8')
    print(json.dumps(reports, indent=2))


if __name__ == '__main__':
    main()
