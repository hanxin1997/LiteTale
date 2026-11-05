import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wild/eink/eink_navigation.dart';
import 'package:wild/eink/eink_overlays.dart';
import 'package:wild/eink/eink_preferences.dart';
import 'package:wild/eink/eink_progress_indicator.dart';
import 'package:wild/eink/eink_theme.dart';
import 'package:wild/pages/auth_cubit.dart';
import 'package:wild/pages/home/index_page.dart';
import 'package:wild/sources/book_source.dart';
import 'package:wild/src/rust/api/wenku8.dart' show PageStatsNovelCover;
import 'package:wild/src/rust/frb_generated.dart';
import 'package:wild/src/rust/wenku8/models.dart';
import 'package:wild/theme/horizontal_page_transitions.dart';
import 'package:wild/theme/material_you.dart';
import 'package:wild/widgets/app_loading_indicator.dart';
import 'package:wild/widgets/expressive_loading_indicator.dart'
    show ExpressiveLoadingIndicator;
import 'package:wild/widgets/platform_controls.dart';

Future<EInkPreferencesCubit> _preference(bool enabled) async {
  final preference = EInkPreferencesCubit(
    read: () async => '',
    write: (_) async {},
  );
  await preference.setEnabled(enabled);
  return preference;
}

Widget _host(
  EInkPreferencesCubit preference,
  Widget home, {
  List<NavigatorObserver> observers = const [],
}) => BlocProvider<EInkPreferencesCubit>.value(
  value: preference,
  child: BlocBuilder<EInkPreferencesCubit, bool>(
    builder: (context, enabled) {
      final normal = materialYouTheme(Brightness.light);
      return MaterialApp(
        themeAnimationDuration: Duration.zero,
        theme: enabled ? einkTheme(normal) : normal,
        navigatorObservers: observers,
        home: home,
      );
    },
  ),
);

class _Observer extends NavigatorObserver {
  Route<dynamic>? last;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    last = route;
  }
}

class _Authenticated extends AuthCubit {
  _Authenticated() : super(sessionInvalidations: const Stream<void>.empty()) {
    emit(const AuthState(status: AuthStatus.authenticated));
  }
}

/// All data is local, synthetic and empty of account information. Unexpected
/// bridge calls fail rather than silently contacting a real source.
class _DiscoveryApi implements RustLibApi {
  int homeLoads = 0;
  int completeLoads = 0;
  int unexpectedCalls = 0;

  @override
  Future<String> crateApiDatabaseLoadProperty({required String key}) async => '';

  @override
  Future<String> crateApiWenku8GetApiHost() async => 'https://www.wenku8.net';

  @override
  Future<List<HomeBlock>> crateApiWenku8Index() async {
    homeLoads++;
    return const [HomeBlock(title: '本地推荐夹具', list: [])];
  }

  @override
  Future<PageStatsNovelCover> crateApiWenku8Articlelist({
    required int fullflag,
    required int page,
  }) async {
    completeLoads++;
    return const PageStatsNovelCover(
      currentPage: 1,
      maxPage: 1,
      records: [],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    unexpectedCalls++;
    throw StateError('Unexpected fixture bridge call: ${invocation.memberName}');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final explicit in [false, true]) {
    for (final enabled in [false, true]) {
      testWidgets(
        '${explicit ? 'explicit' : 'theme'} route '
        '${enabled ? 'has no transition and completes pop' : 'keeps its original slide'}',
        (tester) async {
          final preference = await _preference(enabled);
          addTearDown(preference.close);
          late PageRoute<int> route;
          int? result;
          var completed = false;
          await tester.pumpWidget(
            _host(
              preference,
              Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () {
                      Widget destination(BuildContext context) => Scaffold(
                        key: const ValueKey('destination'),
                        body: TextButton(
                          onPressed: () => Navigator.pop(context, 7),
                          child: const Text('返回'),
                        ),
                      );
                      route = explicit
                          ? HorizontalCoverPageRoute<int>(builder: destination)
                          : MaterialPageRoute<int>(builder: destination);
                      Navigator.push(context, route).then((value) {
                        completed = true;
                        result = value;
                      });
                    },
                    child: const Text('打开'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('打开'));
          await tester.pump();
          await tester.pump();
          final slide = find.ancestor(
            of: find.byKey(const ValueKey('destination')),
            matching: find.byType(SlideTransition),
          );
          if (enabled) {
            expect(route.transitionDuration, Duration.zero);
            expect(route.reverseTransitionDuration, Duration.zero);
            expect(slide, findsNothing);
            expect(route.animation!.value, 1);
            expect(
              tester.getTopLeft(find.byKey(const ValueKey('destination'))),
              Offset.zero,
            );
          } else {
            expect(route.transitionDuration, const Duration(milliseconds: 300));
            expect(slide, findsOneWidget);
            await tester.pump(const Duration(milliseconds: 120));
            expect(
              tester.widget<SlideTransition>(slide).position.value.dx,
              inExclusiveRange(0, 1),
            );
            await tester.pumpAndSettle();
          }
          await tester.tap(find.text('返回'));
          await tester.pump();
          // Normal routes retain their reverse animation and are removed on
          // the following overlay frame. E Ink still asserts immediate removal.
          if (!enabled) await tester.pumpAndSettle();
          await tester.pump();
          expect(completed, isTrue);
          expect(result, 7);
          expect(find.byKey(const ValueKey('destination')), findsNothing);
          expect(find.text('打开'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
        variant: TargetPlatformVariant.only(TargetPlatform.android),
      );
    }
  }

  testWidgets(
    'dialog preserves Flutter 3.29 parameters, result and barrier cleanup',
    (tester) async {
      final preference = await _preference(true);
      final observer = _Observer();
      addTearDown(preference.close);
      String? result;
      var completed = false;
      await tester.pumpWidget(
        _host(
          preference,
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () {
                  // This invocation is also a compile-time regression contract
                  // for the API supported by the project's Flutter 3.29 SDK.
                  showEinkAwareDialog<String>(
                    context: context,
                    barrierDismissible: false,
                    barrierColor: Colors.black26,
                    barrierLabel: '静态对话框遮罩',
                    useSafeArea: true,
                    useRootNavigator: true,
                    routeSettings: const RouteSettings(name: '/fixture-dialog'),
                    anchorPoint: Offset.zero,
                    traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
                    builder: (context) => AlertDialog(
                      title: const Text('等待结果'),
                      content: const EInkProgressIndicator(
                        child: CircularProgressIndicator(),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, '已完成'),
                          child: const Text('完成'),
                        ),
                      ],
                    ),
                  ).then((value) {
                    completed = true;
                    result = value;
                  });
                },
                child: const Text('对话框'),
              ),
            ),
          ),
          observers: [observer],
        ),
      );
      // Full-screen routes may retain their own inert barrier. Compare with
      // the original route rather than mistaking it for a leaked dialog layer.
      final originalBarriers = find.byType(ModalBarrier).evaluate().length;
      final originalAnimatedBarriers =
          find.byType(AnimatedModalBarrier).evaluate().length;
      await tester.tap(find.text('对话框'));
      await tester.pump();
      await tester.pump();
      final dialogRoute = observer.last as DialogRoute<dynamic>;
      expect(dialogRoute.transitionDuration, Duration.zero);
      expect(dialogRoute.reverseTransitionDuration, Duration.zero);
      expect(dialogRoute.barrierDismissible, isFalse);
      expect(dialogRoute.barrierColor, Colors.black26);
      expect(dialogRoute.barrierLabel, '静态对话框遮罩');
      expect(dialogRoute.settings.name, '/fixture-dialog');
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.tapAt(const Offset(8, 8));
      await tester.pump();
      expect(completed, isFalse);
      expect(find.text('等待结果'), findsOneWidget);
      await tester.tap(find.text('完成'));
      await tester.pump();
      await tester.pump();
      expect(completed, isTrue);
      expect(result, '已完成');
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(ModalBarrier), findsNWidgets(originalBarriers));
      expect(
        find.byType(AnimatedModalBarrier),
        findsNWidgets(originalAnimatedBarriers),
      );
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'bottom sheet appears in place, ignores drag and returns its result',
    (tester) async {
      final preference = await _preference(true);
      addTearDown(preference.close);
      String? result;
      await tester.pumpWidget(
        _host(
          preference,
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showAppBottomSheet<String>(
                  context: context,
                  builder: (context) => SizedBox(
                    key: const ValueKey('sheet'),
                    height: 200,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, '已选择'),
                      child: const Text('选择'),
                    ),
                  ),
                ).then((value) => result = value),
                child: const Text('底部弹窗'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('底部弹窗'));
      await tester.pump();
      await tester.pump();
      final finder = find.byKey(const ValueKey('sheet'));
      final position = tester.getTopLeft(finder);
      final gesture = await tester.startGesture(tester.getCenter(finder));
      await gesture.moveBy(const Offset(0, 80));
      await tester.pump();
      expect(tester.getTopLeft(finder), position);
      await gesture.up();
      await tester.tap(find.text('选择'));
      await tester.pump();
      await tester.pump();
      expect(result, '已选择');
      expect(finder, findsNothing);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'progress is static, keeps real values and fits small controls',
    (tester) async {
      final preference = await _preference(true);
      addTearDown(preference.close);
      final progress = ValueNotifier<double>(.25);
      addTearDown(progress.dispose);
      await tester.pumpWidget(
        _host(
          preference,
          Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox.square(
                    dimension: 16,
                    child: EInkProgressIndicator(child: CircularProgressIndicator()),
                  ),
                  const AppLoadingIndicator(size: 16),
                  ValueListenableBuilder<double>(
                    valueListenable: progress,
                    builder: (context, value, _) => EInkProgressIndicator(
                      child: CircularProgressIndicator(value: value),
                    ),
                  ),
                  const SizedBox(
                    width: 100,
                    height: 4,
                    child: EInkProgressIndicator(
                      child: LinearProgressIndicator(value: .4),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('正在加载 25%'), findsOneWidget);
      expect(tester.widget<FractionallySizedBox>(find.byType(FractionallySizedBox)).widthFactor, .4);
      await tester.pump(const Duration(seconds: 2));
      expect(tester.binding.hasScheduledFrame, isFalse);
      progress.value = .75;
      await tester.pump();
      expect(find.text('正在加载 75%'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await preference.setEnabled(false);
      await tester.pump();
      // Bloc's broadcast arrives in a microtask; allow dependent widgets to
      // build their restored children without settling an infinite spinner.
      await tester.pump();
      // Android's original AppLoadingIndicator uses the expressive shape;
      // only the two explicit circular children return to the circular widget.
      expect(find.byType(CircularProgressIndicator), findsNWidgets(2));
      expect(find.byType(ExpressiveLoadingIndicator), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'discovery jumps directly, keeps visited pages and never eagerly loads tabs',
    (tester) async {
      final api = _DiscoveryApi();
      RustLib.initMock(api: api);
      final preference = await _preference(true);
      final auth = _Authenticated();
      final previousSource = activeSource.value;
      activeSource.value = SourceId.wenku8;
      addTearDown(() => activeSource.value = previousSource);
      addTearDown(preference.close);
      addTearDown(auth.close);
      await tester.pumpWidget(
        BlocProvider<AuthCubit>.value(
          value: auth,
          child: _host(preference, const IndexPage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(api.homeLoads, 1);
      expect(api.completeLoads, 0);
      expect(api.unexpectedCalls, 0);
      final tabView = tester.element(find.byType(TabBarView));
      await tester.tap(find.descendant(of: find.byType(EInkTabStrip), matching: find.text('完结')));
      await tester.pump();
      await tester.pump();
      expect(api.completeLoads, 1);
      expect(api.unexpectedCalls, 0);
      // IndexPage exports its own discovery ArticlelistPage. The similarly
      // named legacy standalone page uses another provider and is not this tab.
      final completePage = tester.element(find.byType(ArticlelistPage));
      final pageView = tester.widget<PageView>(find.byType(PageView));
      expect(pageView.controller!.page, 3);
      final gesture = await tester.startGesture(tester.getCenter(find.byType(PageView)));
      await gesture.moveBy(const Offset(200, 0));
      await tester.pump();
      expect(pageView.controller!.page, 3);
      await gesture.up();
      await tester.tap(find.descendant(of: find.byType(EInkTabStrip), matching: find.text('推荐')));
      await tester.pumpAndSettle();
      expect(api.homeLoads, 1);
      await tester.tap(find.descendant(of: find.byType(EInkTabStrip), matching: find.text('完结')));
      await tester.pumpAndSettle();
      expect(tester.element(find.byType(ArticlelistPage)), same(completePage));
      await preference.setEnabled(false);
      await tester.pumpAndSettle();
      expect(tester.element(find.byType(TabBarView)), same(tabView));
      expect(tester.element(find.byType(ArticlelistPage)), same(completePage));
      await preference.setEnabled(true);
      await tester.pumpAndSettle();
      expect(tester.element(find.byType(TabBarView)), same(tabView));
      expect(api.completeLoads, 1);
      expect(api.homeLoads, 1);
      expect(api.unexpectedCalls, 0);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
