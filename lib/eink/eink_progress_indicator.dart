import 'package:flutter/material.dart';
import 'package:wild/eink/eink_policy.dart';

/// Replaces only the visual spinner; asynchronous work and completion callbacks
/// continue normally. Real determinate progress remains visible as a percentage.
class EInkProgressIndicator extends StatelessWidget {
  const EInkProgressIndicator({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!einkEnabled(context)) return child;
    final indicator =
        child is ProgressIndicator ? child as ProgressIndicator : null;
    final value = indicator?.value;
    final percentage =
        value == null ? null : '${(value.clamp(0, 1) * 100).round()}%';
    final label = indicator?.semanticsLabel ?? '正在加载';
    final text = percentage == null ? label : '$label $percentage';
    return Semantics(
      label: label,
      value: indicator?.semanticsValue ?? percentage,
      child: ExcludeSemantics(
        child: _staticPresentation(text, percentage, value),
      ),
    );
  }

  Widget _staticPresentation(String text, String? percentage, double? value) {
    // Keep the thin-bar layout, and only fill it when there is real business
    // progress. An indeterminate wait gets an empty static outlined track.
    if (child is LinearProgressIndicator) {
      return SizedBox(
        width: double.infinity,
        height: (child as LinearProgressIndicator).minHeight ?? 4,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.black),
          ),
          child:
              value == null
                  ? const SizedBox.shrink()
                  : FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: value.clamp(0, 1).toDouble(),
                    child: const ColoredBox(color: Colors.black),
                  ),
        ),
      );
    }
    // Small toolbar spinners and AlertDialog intrinsic sizing must keep working.
    // FittedBox supports both; a LayoutBuilder would break intrinsic layouts.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.hourglass_empty_rounded,
            color: Colors.black,
            size: 32,
          ),
          if (percentage != null || child is! CircularProgressIndicator)
            Text(text, style: const TextStyle(color: Colors.black)),
        ],
      ),
    );
  }
}
