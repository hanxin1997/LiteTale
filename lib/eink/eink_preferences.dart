import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wild/src/rust/api/database.dart';

/// The one capability gate, re-exported by eink_policy.dart for UI callers.
/// A saved preference must never opt a browser or another platform into EPD UI.
bool get supportsEink =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// A device display preference, deliberately separate from settings_v1 and the
/// book/settings snapshot contract. Saving it does not rewrite reader choices.
class EInkPreferencesCubit extends Cubit<bool> {
  EInkPreferencesCubit({
    Future<String> Function()? read,
    Future<void> Function(String)? write,
  }) : _read = read ?? (() => loadProperty(key: propertyKey)),
       _write = write ?? ((value) => saveProperty(key: propertyKey, value: value)),
       _hasInjectedRead = read != null,
       _hasInjectedWrite = write != null,
       super(false);

  static const propertyKey = 'litetale.android_eink_v1';

  final Future<String> Function() _read;
  final Future<void> Function(String) _write;
  final bool _hasInjectedRead;
  final bool _hasInjectedWrite;
  Future<void> _pending = Future<void>.value();
  int _revision = 0;

  Future<void> initialize() {
    // Injected storage is usable by tests on any host. Default storage never
    // touches the Rust bridge outside Android, even if a database has this key.
    if (isClosed || (!supportsEink && !_hasInjectedRead)) {
      return Future<void>.value();
    }
    final revision = _revision;
    return _enqueue(() async {
      var enabled = false;
      try {
        final raw = await _read();
        // Accept only our canonical bool strings. Empty, JSON objects, quoted
        // strings and other corrupt values all safely use the default.
        enabled = raw == 'true';
      } catch (_) {
        // An optional display preference cannot prevent guest startup.
      }
      // A delayed startup read must not undo a user's newer switch operation.
      if (!isClosed && revision == _revision) emit(enabled);
    });
  }

  Future<void> setEnabled(bool enabled) {
    if (isClosed || (!supportsEink && !_hasInjectedWrite)) {
      return Future<void>.value();
    }
    _revision++;
    return _enqueue(() async {
      // Publish only durable values. The caller receives a storage failure and
      // can show an error; subsequent queued operations remain usable.
      await _write(enabled ? 'true' : 'false');
      if (!isClosed) emit(enabled);
    });
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final next = _pending.then((_) async {
      if (!isClosed) await action();
    });
    // Reads and writes share this queue so initialization cannot overtake a
    // pending save. Swallow only the queue's copy; the returned Future retains
    // the original failure for the settings UI.
    _pending = next.catchError((Object _) {});
    return next;
  }
}
