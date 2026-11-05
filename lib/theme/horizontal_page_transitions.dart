import 'package:flutter/material.dart';
import 'package:wild/eink/eink_policy.dart';

/// A page covers its predecessor from the right and uncovers it to the right.
/// The page underneath stays still. No opacity, scale, or shared-element work is
/// performed during the transition.
const horizontalPageTransitionsTheme = PageTransitionsTheme(
  builders: {
    TargetPlatform.android: HorizontalCoverPageTransitionsBuilder(),
    TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    TargetPlatform.fuchsia: HorizontalCoverPageTransitionsBuilder(),
    TargetPlatform.linux: HorizontalCoverPageTransitionsBuilder(),
    TargetPlatform.macOS: HorizontalCoverPageTransitionsBuilder(),
    TargetPlatform.windows: HorizontalCoverPageTransitionsBuilder(),
  },
);

class HorizontalCoverPageTransitionsBuilder extends PageTransitionsBuilder {
  const HorizontalCoverPageTransitionsBuilder();

  // 300 ms spans about 36 frames on a 120 Hz display. Only a translation is
  // animated, so neither page needs an opacity or size animation each frame.
  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 300);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (route.isFirst || einkEnabled(context)) return child;
    return _HorizontalCoverTransition(animation: animation, child: child);
  }
}

/// Used by the independent E Ink theme so standard MaterialPageRoute lifecycle
/// durations are also zero. Ordinary themes retain their existing 300 ms path.
class EInkPageTransitionsBuilder extends PageTransitionsBuilder {
  const EInkPageTransitionsBuilder();

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => Duration.zero;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}

/// Forces the app's full-screen motion even if a host theme replaces the
/// platform page transition defaults after the route has been created.
class HorizontalCoverPageRoute<T> extends MaterialPageRoute<T> {
  HorizontalCoverPageRoute({
    required super.builder,
    super.settings,
    super.fullscreenDialog,
  });

  @override
  Duration get transitionDuration =>
      _einkEnabled ? Duration.zero : const Duration(milliseconds: 300);

  @override
  Duration get reverseTransitionDuration =>
      _einkEnabled ? Duration.zero : const Duration(milliseconds: 300);

  bool get _einkEnabled {
    final routeContext = navigator?.context;
    return routeContext != null && einkEnabled(routeContext, listen: false);
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // A preference change during a running transition presents its final frame
    // immediately. Its controller remains alive so push/pop futures can finish.
    if (einkEnabled(context)) return child;
    return (Theme.of(context).platform == TargetPlatform.iOS
            ? const CupertinoPageTransitionsBuilder()
            : const HorizontalCoverPageTransitionsBuilder())
        .buildTransitions(this, context, animation, secondaryAnimation, child);
  }
}

class _HorizontalCoverTransition extends StatefulWidget {
  const _HorizontalCoverTransition({
    required this.animation,
    required this.child,
  });

  final Animation<double> animation;
  final Widget child;

  @override
  State<_HorizontalCoverTransition> createState() =>
      _HorizontalCoverTransitionState();
}

class _HorizontalCoverTransitionState
    extends State<_HorizontalCoverTransition> {
  late CurvedAnimation _curve;
  late Animation<Offset> _position;

  void _bindAnimation() {
    _curve = CurvedAnimation(
      parent: widget.animation,
      curve: Curves.easeOutQuad,
      reverseCurve: Curves.easeInQuad,
    );
    _position = Tween<Offset>(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).animate(_curve);
  }

  @override
  void initState() {
    super.initState();
    _bindAnimation();
  }

  @override
  void didUpdateWidget(_HorizontalCoverTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation) {
      _curve.dispose();
      _bindAnimation();
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _position,
      textDirection: TextDirection.ltr,
      child: RepaintBoundary(child: widget.child),
    );
  }
}
