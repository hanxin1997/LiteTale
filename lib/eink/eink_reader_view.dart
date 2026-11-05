import 'package:flutter/material.dart';

/// A stationary sheet: the drag is measured without moving or repainting the
/// paper. Only a completed horizontal gesture can request one page turn.
class EInkReaderView extends StatefulWidget {
  const EInkReaderView({
    super.key,
    required this.child,
    required this.onTurn,
    required this.onTapUp,
    this.swipeThreshold = 48,
  });

  final Widget child;
  final ValueChanged<int> onTurn;
  final GestureTapUpCallback onTapUp;
  final double swipeThreshold;

  @override
  State<EInkReaderView> createState() => _EInkReaderViewState();
}

class _EInkReaderViewState extends State<EInkReaderView> {
  double _distance = 0;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTapUp: widget.onTapUp,
    onHorizontalDragStart: (_) => _distance = 0,
    onHorizontalDragUpdate: (details) => _distance += details.delta.dx,
    onHorizontalDragCancel: () => _distance = 0,
    onHorizontalDragEnd: (_) {
      final distance = _distance;
      _distance = 0;
      // Ignore fling velocity: a short accidental gesture must not turn a page.
      if (distance.abs() >= widget.swipeThreshold) {
        widget.onTurn(distance < 0 ? 1 : -1);
      }
    },
    child: RepaintBoundary(child: widget.child),
  );
}
