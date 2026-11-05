import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wild/eink/eink_preferences.dart';

export 'package:wild/eink/eink_preferences.dart' show supportsEink;

/// Existing standalone widgets and tests need no new provider to keep their
/// previous behavior. Only the optional Android preference activates this path.
bool einkEnabled(BuildContext context, {bool listen = true}) {
  if (!supportsEink) return false;
  final preference =
      listen
          ? context.watch<EInkPreferencesCubit?>()
          : context.read<EInkPreferencesCubit?>();
  return preference?.state ?? false;
}
