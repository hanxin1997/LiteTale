import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wild/eink/eink_policy.dart';
import 'package:wild/eink/eink_preferences.dart';
import 'package:wild/settings/settings_widgets.dart';

/// Device display settings are independent of the book and its saved theme.
class EInkSetting extends StatefulWidget {
  const EInkSetting({super.key});

  @override
  State<EInkSetting> createState() => _EInkSettingState();
}

class _EInkSettingState extends State<EInkSetting> {
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    if (!supportsEink) return const SizedBox.shrink();
    // Standalone settings previews and older hosts may omit this new provider.
    final preferences = context.watch<EInkPreferencesCubit?>();
    if (preferences == null) return const SizedBox.shrink();
    return SettingsSwitch(
      key: const ValueKey('eink-mode-switch'),
      icon: Icons.chrome_reader_mode_outlined,
      title: '墨水屏模式',
      description: _saving
          ? '正在保存…'
          : '白底深色文字、直接翻页，关闭主要动效；关闭后恢复原显示设置',
      value: preferences.state,
      onChanged:
          _saving
              ? null
              : (value) async {
                setState(() => _saving = true);
                try {
                  await settingsAction(context, () => preferences.setEnabled(value));
                } finally {
                  if (mounted) setState(() => _saving = false);
                }
              },
    );
  }
}
