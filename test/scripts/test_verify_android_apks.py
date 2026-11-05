"""Offline verifier regressions; SDK output and tiny ELF ZIP fixtures are synthetic."""
import importlib.util
import os
from pathlib import Path
import struct
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch
import zipfile


SCRIPT = Path(__file__).resolve().parents[2] / 'tools' / 'verify_android_apks.py'
SPEC = importlib.util.spec_from_file_location('verify_android_apks', SCRIPT)
verifier = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(verifier)


class AndroidToolsTests(unittest.TestCase):
    def test_linux_uses_sdk_root_and_java_from_path(self):
        environment = {'ANDROID_SDK_ROOT': '/opt/android', 'PATH': '/usr/bin'}
        tools = verifier.AndroidTools('36.0.0', environment=environment, windows=False)
        with patch.object(verifier.subprocess, 'run', return_value=
                          subprocess.CompletedProcess([], 0, 'verified', '')) as run:
            self.assertEqual(tools.run('apksigner', 'verify', 'app.apk'), 'verified')
        self.assertEqual(run.call_args.args[0], [
            str(Path('/opt/android/build-tools/36.0.0/apksigner')), 'verify', 'app.apk'])
        self.assertEqual(run.call_args.kwargs['env'], environment)
        self.assertNotIn('JAVA_HOME', environment)

    def test_android_home_wins_and_configured_java_is_preserved(self):
        environment = {'ANDROID_HOME': '/primary', 'ANDROID_SDK_ROOT': '/other',
                       'JAVA_HOME': '/java17', 'PATH': '/usr/bin'}
        tools = verifier.AndroidTools(environment=environment, windows=False)
        self.assertEqual(tools.build_tools, Path('/primary/build-tools/35.0.0'))
        self.assertEqual(tools.environment['JAVA_HOME'], '/java17')
        self.assertEqual(tools.environment['PATH'], str(Path('/java17/bin')) + os.pathsep + '/usr/bin')
        self.assertEqual(environment['PATH'], '/usr/bin', 'Caller environment must not be mutated')

    def test_windows_preserves_local_defaults_and_executable_suffixes(self):
        tools = verifier.AndroidTools(environment={'PATH': 'original-path'}, windows=True)
        self.assertEqual(tools.build_tools, Path('D:/Codex-Migrated/Android/Sdk/build-tools/35.0.0'))
        self.assertEqual(tools.environment['JAVA_HOME'], r'D:\CodexToolchains\jdk17\jdk-17.0.16+8')
        with patch.object(verifier.subprocess, 'run', return_value=
                          subprocess.CompletedProcess([], 0, '', '')) as run:
            tools.run('aapt', 'dump', 'badging', 'app.apk')
            tools.run('apksigner', 'verify', 'app.apk')
            tools.run('zipalign', '-c', '4', 'app.apk')
        self.assertEqual([Path(call.args[0][0]).name for call in run.call_args_list],
                         ['aapt.exe', 'apksigner.bat', 'zipalign.exe'])

    def test_linux_without_sdk_fails_instead_of_using_windows_path(self):
        with self.assertRaisesRegex(RuntimeError, 'ANDROID_HOME or ANDROID_SDK_ROOT'):
            verifier.AndroidTools(environment={'PATH': '/usr/bin'}, windows=False)

    def test_sdk_verification_failure_is_fatal(self):
        tools = verifier.AndroidTools(environment={'ANDROID_HOME': '/sdk'}, windows=False)
        with patch.object(verifier.subprocess, 'run', return_value=
                          subprocess.CompletedProcess([], 1, '', 'APK signature rejected')):
            with self.assertRaisesRegex(RuntimeError, 'APK signature rejected'):
                tools.run('apksigner', 'verify', 'app.apk')


class ApkVerificationTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix='litetale-apk-verifier-'))
        self.apk_directory = self.root / 'build/app/outputs/flutter-apk'
        self.apk_directory.mkdir(parents=True)
        self.signatures = {'arm64-v8a': 'a' * 64, 'x86_64': 'a' * 64}
        self.version = '1.1.1'
        self.build_number = 100001
        self.calls = []
        self.write_apk('arm64-v8a', 183)
        self.write_apk('x86_64', 62)

    def tearDown(self):
        # Only remove the two named synthetic files and their empty directories.
        for abi in ('arm64-v8a', 'x86_64'):
            (self.apk_directory / f'app-{abi}-release.apk').unlink(missing_ok=True)
        for directory in (self.apk_directory, self.apk_directory.parent,
                          self.root / 'build/app', self.root / 'build', self.root):
            directory.rmdir()

    def write_apk(self, abi, machine, *, alignment=16384, include_runtime=True):
        # A single ELF64 load-segment header exercises the actual alignment parser.
        elf = bytearray(120)
        elf[:6] = b'\x7fELF\x02\x01'
        struct.pack_into('<H', elf, 18, machine)
        struct.pack_into('<Q', elf, 32, 64)
        struct.pack_into('<HH', elf, 54, 56, 1)
        struct.pack_into('<I', elf, 64, 1)
        struct.pack_into('<Q', elf, 112, alignment)
        libraries = ['libapp.so', 'libflutter.so', 'librust_lib_wild.so']
        if include_runtime:
            libraries.append('libc++_shared.so')
        with zipfile.ZipFile(self.apk_directory / f'app-{abi}-release.apk', 'w') as archive:
            for name in libraries:
                archive.writestr(f'lib/{abi}/{name}', elf)

    def sdk_run(self, tool, *params):
        self.calls.append((tool, params))
        apk = next(p for p in params if str(p).endswith('.apk'))
        abi = 'arm64-v8a' if 'arm64-v8a' in str(apk) else 'x86_64'
        if tool == 'apksigner':
            return ('Signer #1 certificate SHA-256 digest: ' + self.signatures[abi]
                    + '\nSource Stamp Signer certificate SHA-256 digest: ignored')
        if tool == 'aapt' and params[1] == 'badging':
            code = (2000 if abi == 'arm64-v8a' else 4000) + self.build_number
            return (f"package: name='io.github.metammy07.novels' versionCode='{code}' "
                    f"versionName='{self.version}'\napplication-label:'LiteTale'")
        return ''

    def verify(self):
        # Mock only external Android executables; ZIP and ELF checks use real files.
        tools = Mock()
        tools.run.side_effect = self.sdk_run
        return verifier.verify_apks(self.root, '1.1.1', 100001, tools)

    def test_both_abis_keep_version_offsets_and_pass_native_library_checks(self):
        reports = self.verify()
        self.assertEqual([row['versionCode'] for row in reports], [102001, 104001])
        self.assertEqual([row['abi'] for row in reports], ['arm64-v8a', 'x86_64'])
        self.assertTrue(all(row['alignment16KB'] == 'passed' for row in reports))
        self.assertTrue(all(len(row['sha256']) == 64 for row in reports))
        self.assertEqual(sum(tool == 'zipalign' for tool, _ in self.calls), 2)

    def test_different_signing_keys_cannot_be_published_as_one_release(self):
        self.signatures['x86_64'] = 'b' * 64
        with self.assertRaisesRegex(AssertionError, 'signing certificates differ'):
            self.verify()

    def test_missing_cpp_runtime_is_rejected(self):
        self.write_apk('arm64-v8a', 183, include_runtime=False)
        with self.assertRaises(AssertionError):
            self.verify()

    def test_4kb_native_library_is_rejected(self):
        self.write_apk('x86_64', 62, alignment=4096)
        with self.assertRaises(AssertionError):
            self.verify()

    def test_wrong_native_architecture_is_rejected(self):
        self.write_apk('arm64-v8a', 62)
        with self.assertRaises(AssertionError):
            self.verify()

    def test_wrong_version_code_is_rejected(self):
        self.build_number = 79
        with self.assertRaises(AssertionError):
            self.verify()


if __name__ == '__main__':
    unittest.main()
