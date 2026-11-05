import 'package:flutter/widgets.dart';
import 'package:wild/eink/eink_policy.dart';

/// Supplies a reduced-motion hint without freezing ticker completion callbacks.
/// Explicit routes, loaders and reader surfaces also handle the display policy.
class EInkScope extends StatelessWidget {
  const EInkScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final enabled = einkEnabled(context);
    final mediaQuery = MediaQuery.of(context);
    final scrollBehavior = ScrollConfiguration.of(context);
    // Always retain both wrappers, including when disabled, so toggling the
    // preference preserves the Navigator and every existing route's state.
    return MediaQuery(
      data: enabled ? mediaQuery.copyWith(disableAnimations: true) : mediaQuery,
      child: ScrollConfiguration(
        // copyWith delegates physics, dragging devices and platform behavior
        // to the original configuration. Only decorative edge paint is removed.
        behavior:
            enabled
                ? scrollBehavior.copyWith(overscroll: false)
                : scrollBehavior,
        child: child,
      ),
    );
  }
}
