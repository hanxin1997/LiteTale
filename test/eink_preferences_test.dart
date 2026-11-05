import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wild/eink/eink_preferences.dart';
import 'package:wild/src/rust/frb_generated.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final bridge = _PropertyApi();
  setUpAll(() => RustLib.initMock(api: bridge));
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    bridge.values.clear();
    bridge.reads.clear();
    bridge.writes.clear();
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('defaults off and restores only canonical bool strings', () async {
    for (final raw in [
      '',
      'false',
      'TRUE',
      ' true ',
      '1',
      'null',
      '"true"',
      '{"enabled":true}',
      'true',
    ]) {
      final cubit = EInkPreferencesCubit(read: () async => raw);
      expect(cubit.state, isFalse);
      await cubit.initialize();
      expect(cubit.state, raw == 'true', reason: 'stored value: $raw');
      await cubit.close();
    }
  });

  test('read failure leaves startup usable and disabled', () async {
    final cubit = EInkPreferencesCubit(
      read: () async => throw StateError('unavailable storage'),
    );
    addTearDown(cubit.close);
    await cubit.initialize();
    expect(cubit.state, isFalse);
  });

  test('default Android bridge uses only the independent device key', () async {
    final cubit = EInkPreferencesCubit();
    addTearDown(cubit.close);
    await cubit.initialize();
    expect(cubit.state, isFalse);
    await cubit.setEnabled(true);
    expect(bridge.reads, ['litetale.android_eink_v1']);
    expect(bridge.writes, [('litetale.android_eink_v1', 'true')]);

    final restored = EInkPreferencesCubit();
    addTearDown(restored.close);
    await restored.initialize();
    expect(restored.state, isTrue);
  });

  test('non-Android default storage performs no bridge calls', () async {
    for (final platform in TargetPlatform.values) {
      if (platform == TargetPlatform.android) continue;
      debugDefaultTargetPlatformOverride = platform;
      final cubit = EInkPreferencesCubit();
      await cubit.initialize();
      await cubit.setEnabled(true);
      expect(cubit.state, isFalse, reason: '$platform');
      await cubit.close();
    }
    expect(bridge.reads, isEmpty);
    expect(bridge.writes, isEmpty);
  });

  test('rapid requests serialize and publish only after durable save', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    final stored = <String>[];
    final emitted = <bool>[];
    var inFlight = 0;
    var maxInFlight = 0;
    final cubit = EInkPreferencesCubit(
      write: (value) async {
        inFlight++;
        if (inFlight > maxInFlight) maxInFlight = inFlight;
        if (!started.isCompleted) {
          started.complete();
          await release.future;
        }
        stored.add(value);
        inFlight--;
      },
    );
    addTearDown(cubit.close);
    final subscription = cubit.stream.listen(emitted.add);
    addTearDown(subscription.cancel);

    final first = cubit.setEnabled(true);
    await started.future;
    final second = cubit.setEnabled(false);
    final third = cubit.setEnabled(true);
    expect(cubit.state, isFalse, reason: 'the first save is still pending');
    expect(stored, isEmpty);

    release.complete();
    await Future.wait([first, second, third]);
    await Future<void>.delayed(Duration.zero);
    expect(maxInFlight, 1);
    expect(stored, ['true', 'false', 'true']);
    expect(emitted, [true, false, true]);
    expect(cubit.state, isTrue);
  });

  test('failed save keeps the durable state and the queue can recover', () async {
    var attempts = 0;
    final cubit = EInkPreferencesCubit(
      read: () async => 'true',
      write: (_) async {
        if (++attempts == 1) throw StateError('save failed');
      },
    );
    addTearDown(cubit.close);
    await cubit.initialize();
    await expectLater(cubit.setEnabled(false), throwsA(isA<StateError>()));
    expect(cubit.state, isTrue);
    await cubit.setEnabled(false);
    expect(attempts, 2);
    expect(cubit.state, isFalse);
  });

  test('a slow startup read cannot publish over a newer user choice', () async {
    final readStarted = Completer<void>();
    final readResult = Completer<String>();
    final emitted = <bool>[];
    final stored = <String>[];
    final cubit = EInkPreferencesCubit(
      read: () {
        readStarted.complete();
        return readResult.future;
      },
      write: (value) async => stored.add(value),
    );
    addTearDown(cubit.close);
    final subscription = cubit.stream.listen(emitted.add);
    addTearDown(subscription.cancel);
    final loading = cubit.initialize();
    await readStarted.future;
    final saving = cubit.setEnabled(false);
    readResult.complete('true');
    await Future.wait([loading, saving]);
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state, isFalse);
    expect(emitted, isNot(contains(true)));
    expect(stored, ['false']);
  });

  test('initialization waits for an in-flight save before reading', () async {
    final writeStarted = Completer<void>();
    final release = Completer<void>();
    final calls = <String>[];
    var stored = 'false';
    final cubit = EInkPreferencesCubit(
      read: () async {
        calls.add('read');
        return stored;
      },
      write: (value) async {
        calls.add('write:start');
        writeStarted.complete();
        await release.future;
        stored = value;
        calls.add('write:end');
      },
    );
    addTearDown(cubit.close);
    final saving = cubit.setEnabled(true);
    await writeStarted.future;
    final loading = cubit.initialize();
    expect(calls, ['write:start']);
    release.complete();
    await Future.wait([saving, loading]);
    expect(calls, ['write:start', 'write:end', 'read']);
    expect(cubit.state, isTrue);
  });
}

/// Counts the actual default bridge boundary without loading a native library.
class _PropertyApi implements RustLibApi {
  final values = <String, String>{};
  final reads = <String>[];
  final writes = <(String, String)>[];

  @override
  Future<String> crateApiDatabaseLoadProperty({required String key}) async {
    reads.add(key);
    return values[key] ?? '';
  }

  @override
  Future<void> crateApiDatabaseSaveProperty({
    required String key,
    required String value,
  }) async {
    writes.add((key, value));
    values[key] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected native call: ${invocation.memberName}');
}
