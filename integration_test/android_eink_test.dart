import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wild/main.dart' as app;
import 'package:wild/cubits/reader_curl_cubit.dart';
import 'package:wild/eink/eink_preferences.dart';
import 'package:wild/eink/eink_reader_view.dart';
import 'package:wild/pages/home_page.dart';
import 'package:wild/pages/novel/reader_cubit.dart';
import 'package:wild/pages/novel/reader_page.dart';
import 'package:wild/pages/novel/reader_type_cubit.dart';
import 'package:wild/pages/update_cubit.dart';
import 'package:wild/settings/settings_page.dart';
import 'package:wild/settings/data_snapshot.dart';
import 'package:wild/settings/reading_statistics.dart';
import 'package:wild/services/reading_progress.dart';
import 'package:wild/src/rust/api/database.dart' as database;
import 'package:wild/sources/book_source.dart';
import 'package:wild/sources/source_api.dart' as api;
import 'package:wild/theme/horizontal_page_transitions.dart';

import 'multi_source_test.dart' show FixtureSource;

/// Synthetic book data only. This exercises the real reader/storage/platform
/// chain; it does not verify an account or the panel's physical refresh modes.
class _EinkFixture extends FixtureSource {
  _EinkFixture() : super('');

  @override
  Future<SourceChapter> chapter(String aid, String cid) async => SourceChapter(
    List.generate(100, (index) => '第 $index 段：墨水屏适配测试，点击或滑动后直接换页。').join('\n'),
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android E Ink switch, reader, stored choice and snapshot isolation', (
    tester,
  ) async {
    Future<void> until(bool Function() ready, String description) async {
      final elapsed = Stopwatch()..start();
      while (!ready() && elapsed.elapsed < const Duration(seconds: 30)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(ready(), isTrue, reason: description);
    }

    final fixture = _EinkFixture();
    final originalSource = api.bookSources[SourceId.lightNovelShelf]!;
    api.bookSources[SourceId.lightNovelShelf] = fixture;
    addTearDown(() => api.bookSources[SourceId.lightNovelShelf] = originalSource);
    await app.main();
    await until(() => find.byType(HomePage).evaluate().isNotEmpty, '应用初始化');
    final home = tester.element(find.byType(HomePage));
    // The production startup may check releases. Let that existing request
    // settle, then dismiss its optional overlay before exercising settings.
    await until(
      () => home.read<UpdateCubit>().state.phase != UpdatePhase.checking,
      '启动更新检查结束',
    );
    if (find.text('发现新版本').evaluate().isNotEmpty) {
      await tester.tap(find.text('我知道了'));
      await tester.pump();
    }
    final navigator = Navigator.of(home);
    final eink = home.read<EInkPreferencesCubit>();
    final type = home.read<ReaderTypeCubit>();
    final curl = home.read<ReaderCurlCubit>();
    final statistics = home.read<ReadingStatisticsCubit>();
    final originalStatistics = await database.loadProperty(
      key: readingStatisticsPropertyKey,
    );
    final oldEink = eink.state, oldType = type.state, oldCurl = curl.state;
    addTearDown(() async {
      // Dispose any failed-test reader before restoring storage, then wait for
      // accepted writes so fixture history cannot reappear after cleanup.
      navigator.popUntil((route) => route.isFirst);
      await tester.pumpAndSettle();
      await ReadingProgressQueue.instance.flush();
      await statistics.persist();
      await database.saveProperty(
        key: readingStatisticsPropertyKey,
        value: originalStatistics,
      );
      await statistics.reload();
      await eink.setEnabled(oldEink);
      await type.updateType(oldType);
      await curl.setEnabled(oldCurl);
      await api.deleteHistoryByNovelId(novelId: fixture.book.aid);
    });

    await eink.setEnabled(false);
    await type.updateType(ReaderType.html);
    await curl.setEnabled(true);
    navigator.push(HorizontalCoverPageRoute<void>(
      builder: (_) => const SettingsPage(),
    ));
    await tester.pumpAndSettle();
    final toggle = find.descendant(
      of: find.byKey(const ValueKey('eink-mode-switch')),
      matching: find.byType(Switch),
    );
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await until(() => eink.state, '开关保存并生效');
    await tester.pumpAndSettle();
    expect(type.state, ReaderType.html);
    expect(curl.state, isTrue);
    final restored = EInkPreferencesCubit();
    await restored.initialize();
    expect(restored.state, isTrue);
    await restored.close();

    // Application snapshots exclude the device preference in both merge and
    // overwrite imports. Read the same storage again after each real restore.
    final snapshots = DataSnapshotService();
    final snapshot = await snapshots.build(
      bookshelves: false,
      reading: false,
      settings: true,
    );
    expect(snapshot.json, isNot(contains(EInkPreferencesCubit.propertyKey)));
    for (final overwrite in [false, true]) {
      await snapshots.restore(snapshot, overwrite: overwrite);
      final check = EInkPreferencesCubit();
      await check.initialize();
      expect(check.state, isTrue);
      await check.close();
    }

    navigator.pop();
    await tester.pumpAndSettle();
    final detail = await fixture.detail(fixture.book.aid);
    navigator.pushNamed('/novel/reader', arguments: {
      'novelId': fixture.book.aid,
      'chapterId': detail.volumes.first.chapters.first.cid,
      'title': detail.info.title,
      'novelInfo': detail.info,
      'volumes': detail.volumes,
    });
    await until(() => find.byType(EInkReaderView).evaluate().isNotEmpty, '静态分页正文');
    final reader = tester.element(find.byType(EInkReaderView)).read<ReaderCubit>();
    final before = reader.state as ReaderLoaded;
    final view = find.byType(EInkReaderView);
    final rect = tester.getRect(view);
    // A saved tapToTurn=false is valid; a swipe exercises paging in both cases.
    await tester.drag(view, const Offset(-180, 0));
    await tester.pump();
    expect((reader.state as ReaderLoaded).currentPageIndex,
        before.layout.firstPage(before.layout.viewIndex(before.currentPageIndex) + 1));
    expect(find.byType(PageView), findsNothing);
    final page = (reader.state as ReaderLoaded).currentPageIndex;
    await tester.tapAt(rect.center);
    await tester.pump();
    expect((reader.state as ReaderLoaded).showControls, isTrue);
    expect((reader.state as ReaderLoaded).currentPageIndex, page);
    expect(find.byType(ReaderPage), findsOneWidget);
    navigator.pop();
    await tester.pumpAndSettle();

    await eink.setEnabled(false);
    await tester.pumpAndSettle();
    expect(type.state, ReaderType.html);
    expect(curl.state, isTrue);
    expect(tester.takeException(), isNull);
  }, skip: !Platform.isAndroid);
}
