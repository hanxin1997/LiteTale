import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wild/eink/eink_policy.dart';
import 'package:wild/eink/eink_preferences.dart';
import 'package:wild/eink/eink_scope.dart';
import 'package:wild/eink/eink_setting.dart';
import 'package:wild/eink/eink_theme.dart';
import 'package:wild/settings/settings_preferences.dart';
import 'package:wild/settings/settings_theme.dart';
import 'package:wild/theme/imported_font_theme.dart';

void main() {
  // Platform variants restore Flutter's debug override before its invariant
  // checks; an ordinary tearDown runs too late for testWidgets.
  testWidgets('Android switch waits for saving and can restore normal mode', (
    tester,
  ) async {
    final releaseFirstSave = Completer<void>();
    final stored = <String>[];
    final preferences = EInkPreferencesCubit(
      write: (value) async {
        if (stored.isEmpty) await releaseFirstSave.future;
        stored.add(value);
      },
    );
    addTearDown(preferences.close);
    await tester.pumpWidget(
      BlocProvider.value(
        value: preferences,
        child: const MaterialApp(home: Scaffold(body: EInkSetting())),
      ),
    );

    expect(find.text('墨水屏模式'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    await tester.tap(find.text('墨水屏模式'));
    await tester.pump();
    expect(find.text('正在保存…'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);

    releaseFirstSave.complete();
    await tester.pumpAndSettle();
    expect(preferences.state, isTrue);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    await tester.tap(find.text('墨水屏模式'));
    await tester.pumpAndSettle();
    expect(preferences.state, isFalse);
    expect(stored, ['true', 'false']);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('missing optional provider leaves old standalone hosts disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => EInkScope(child: child!),
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                Text('policy:${einkEnabled(context)}'),
                Text('motion:${MediaQuery.disableAnimationsOf(context)}'),
                const EInkSetting(),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('policy:false'), findsOneWidget);
    expect(find.text('motion:false'), findsOneWidget);
    expect(find.text('墨水屏模式'), findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  for (final platform in [
    TargetPlatform.iOS,
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.fuchsia,
  ]) {
    testWidgets('$platform ignores even an enabled stored preference', (
      tester,
    ) async {
      // Give each platform a fresh preference and mounted widget tree.
      final preferences = EInkPreferencesCubit(read: () async => 'true');
      addTearDown(preferences.close);
      await preferences.initialize();
      expect(preferences.state, isTrue);
      await tester.pumpWidget(
        BlocProvider.value(
          value: preferences,
          child: MaterialApp(
            builder: (context, child) => EInkScope(child: child!),
            home: Scaffold(
              body: Builder(
                builder: (context) => Column(
                  children: [
                    Text('policy:${einkEnabled(context)}'),
                    Text('motion:${MediaQuery.disableAnimationsOf(context)}'),
                    const EInkSetting(),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      expect(supportsEink, isFalse, reason: '$platform');
      expect(find.text('policy:false'), findsOneWidget);
      expect(find.text('motion:false'), findsOneWidget);
      expect(find.text('墨水屏模式'), findsNothing);
      expect(tester.takeException(), isNull, reason: '$platform');
    }, variant: TargetPlatformVariant.only(platform));
  }

  testWidgets('scope preserves route state, scrolling physics and inertia', (
    tester,
  ) async {
    final preferences = EInkPreferencesCubit(write: (_) async {});
    addTearDown(preferences.close);
    final navigatorKey = GlobalKey<NavigatorState>();
    final pageKey = GlobalKey<_PreservedPageState>();
    const behavior = _DecoratedScrollBehavior();
    await tester.pumpWidget(
      BlocProvider.value(
        value: preferences,
        child: MaterialApp(
          navigatorKey: navigatorKey,
          scrollBehavior: behavior,
          builder: (context, child) => EInkScope(child: child!),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => _PreservedPage(key: pageKey),
                  ),
                ),
                child: const Text('打开列表'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开列表'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('计数:0'));
    await tester.pumpAndSettle();
    final navigator = navigatorKey.currentState;
    final page = pageKey.currentState!;
    page.scroll.jumpTo(180);
    await tester.pump();
    final originalPhysics = ScrollConfiguration.of(
      page.pageContext,
    ).getScrollPhysics(page.pageContext);
    expect(find.byKey(const ValueKey('decorative-edge')), findsOneWidget);

    for (final enabled in [true, false]) {
      await preferences.setEnabled(enabled);
      await tester.pump();
      expect(navigatorKey.currentState, same(navigator));
      expect(pageKey.currentState, same(page));
      expect(page.count, 1);
      expect(page.scroll.offset, 180);
      expect(MediaQuery.disableAnimationsOf(page.pageContext), enabled);
      expect(TickerMode.of(page.pageContext), isTrue);
      final physics = ScrollConfiguration.of(
        page.pageContext,
      ).getScrollPhysics(page.pageContext);
      expect(physics, same(originalPhysics));
      expect(
        physics.createBallisticSimulation(page.scroll.position, 600),
        isNotNull,
        reason: 'normal list inertia is retained',
      );
      expect(
        find.byKey(const ValueKey('decorative-edge')),
        enabled ? findsNothing : findsOneWidget,
      );
    }
    // Still a usable Navigator after both policy changes.
    navigator!.pop();
    await tester.pumpAndSettle();
    expect(find.text('打开列表'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('disabled scope preserves the host reduced-motion preference', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: EInkScope(child: child!),
        ),
        home: Builder(
          builder: (context) => Text(
            'host-motion:${MediaQuery.disableAnimationsOf(context)}',
          ),
        ),
      ),
    );
    expect(find.text('host-motion:true'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  test('high-contrast theme preserves imported typography and regional glyphs', () {
    final source = ThemeData.dark().copyWith(
      textTheme: ThemeData.dark().textTheme.copyWith(
        bodyLarge: const TextStyle(fontSize: 23, height: 1.7),
      ),
    );
    final original = applySettingsTheme(
      applyImportedAppFont(source, 'ImportedFixture'),
      const SettingsPreferences(hanVariant: 'zh-TW'),
    );
    final theme = einkTheme(original);
    final before = original.textTheme.bodyLarge!;
    final after = theme.textTheme.bodyLarge!;
    expect(after.fontFamily, before.fontFamily);
    expect(after.fontFamilyFallback, before.fontFamilyFallback);
    expect(after.locale, const Locale('zh', 'TW'));
    expect(after.fontSize, before.fontSize);
    expect(after.height, before.height);
    expect(theme.brightness, Brightness.light);
    expect(theme.scaffoldBackgroundColor, Colors.white);
    expect(theme.colorScheme.surface, Colors.white);
    expect(_contrast(theme.colorScheme.onSurface, theme.colorScheme.surface),
        greaterThanOrEqualTo(7));
    expect(_contrast(theme.colorScheme.onSurfaceVariant, theme.colorScheme.surface),
        greaterThanOrEqualTo(7));
    for (final color in [
      theme.colorScheme.primary,
      theme.colorScheme.primaryContainer,
      theme.colorScheme.secondary,
      theme.colorScheme.secondaryContainer,
      theme.colorScheme.tertiary,
      theme.colorScheme.tertiaryContainer,
      theme.colorScheme.surface,
      theme.colorScheme.onSurface,
      theme.colorScheme.outline,
      theme.colorScheme.error,
    ]) {
      expect(color.a, 1);
      expect(color.r, color.g);
      expect(color.g, color.b);
    }
    expect(theme.splashFactory, same(NoSplash.splashFactory));
    expect(theme.cardTheme.elevation, 0);
    expect(theme.dialogTheme.elevation, 0);
    final routeBuilder = theme.pageTransitionsTheme.builders[TargetPlatform.android]!;
    expect(routeBuilder.transitionDuration, Duration.zero);
    expect(routeBuilder.reverseTransitionDuration, Duration.zero);
    expect(
      theme.pageTransitionsTheme.builders[TargetPlatform.iOS],
      same(original.pageTransitionsTheme.builders[TargetPlatform.iOS]),
    );
    // Derivation must not overwrite the old theme used when the switch closes.
    expect(original.brightness, Brightness.dark);
    expect(original.textTheme.bodyLarge!.fontFamily, 'ImportedFixture');
  });

  test('selected and disabled controls remain distinct with readable colors', () {
    final theme = einkTheme(ThemeData.light());
    final style = theme.filledButtonTheme.style!;
    const disabled = {WidgetState.disabled};
    const selected = {WidgetState.selected};
    final activeInk = style.foregroundColor!.resolve({})!;
    final activePaper = style.backgroundColor!.resolve({})!;
    final disabledInk = style.foregroundColor!.resolve(disabled)!;
    final disabledPaper = style.backgroundColor!.resolve(disabled)!;
    expect(activePaper, isNot(disabledPaper));
    expect(_contrast(activeInk, activePaper), greaterThanOrEqualTo(7));
    expect(_contrast(disabledInk, disabledPaper), greaterThanOrEqualTo(4.5));
    expect(
      theme.switchTheme.trackColor!.resolve(selected),
      isNot(theme.switchTheme.trackColor!.resolve({})),
    );
    expect(
      theme.switchTheme.thumbColor!.resolve(selected),
      isNot(theme.switchTheme.thumbColor!.resolve(disabled)),
    );
    expect(theme.checkboxTheme.side, isNot(BorderSide.none));
    expect(theme.inputDecorationTheme.focusedBorder!.borderSide.width,
        greaterThan(theme.inputDecorationTheme.enabledBorder!.borderSide.width));
  });

  test('existing colored button styles cannot override E Ink paint', () {
    const button = ButtonStyle(
      backgroundColor: WidgetStatePropertyAll(Colors.red),
      foregroundColor: WidgetStatePropertyAll(Colors.yellow),
      overlayColor: WidgetStatePropertyAll(Colors.blue),
      elevation: WidgetStatePropertyAll(8),
      minimumSize: WidgetStatePropertyAll(Size(130, 52)),
      padding: WidgetStatePropertyAll(EdgeInsets.all(17)),
    );
    final source = ThemeData.light().copyWith(
      filledButtonTheme: const FilledButtonThemeData(style: button),
    );
    final style = einkTheme(source).filledButtonTheme.style!;
    expect(style.backgroundColor!.resolve({}), const Color(0xFF101010));
    expect(style.foregroundColor!.resolve({}), Colors.white);
    expect(style.overlayColor!.resolve({WidgetState.pressed}), Colors.transparent);
    expect(style.elevation!.resolve({}), 0);
    expect(style.minimumSize!.resolve({}), const Size(130, 52));
    expect(style.padding!.resolve({}), const EdgeInsets.all(17));
    expect(source.filledButtonTheme.style!.backgroundColor!.resolve({}), Colors.red);
  });
}

double _contrast(Color a, Color b) {
  final aLuminance = a.computeLuminance();
  final bLuminance = b.computeLuminance();
  return (math.max(aLuminance, bLuminance) + .05) /
      (math.min(aLuminance, bLuminance) + .05);
}

class _DecoratedScrollBehavior extends MaterialScrollBehavior {
  const _DecoratedScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => KeyedSubtree(key: const ValueKey('decorative-edge'), child: child);
}

class _PreservedPage extends StatefulWidget {
  const _PreservedPage({super.key});

  @override
  State<_PreservedPage> createState() => _PreservedPageState();
}

class _PreservedPageState extends State<_PreservedPage> {
  final scroll = ScrollController();
  late BuildContext pageContext;
  int count = 0;

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    pageContext = context;
    return Scaffold(
      appBar: AppBar(title: const Text('活动路由')),
      body: ListView(
        controller: scroll,
        children: [
          TextButton(
            onPressed: () => setState(() => count++),
            child: Text('计数:$count'),
          ),
          for (var i = 0; i < 40; i++)
            SizedBox(height: 80, child: Text('章节 $i')),
        ],
      ),
    );
  }
}
