import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wild/eink/eink_reader_view.dart';
import 'package:wild/models/reader_document.dart';
import 'package:wild/models/reader_page.dart' as model;
import 'package:wild/pages/novel/reader_cubit.dart';
import 'package:wild/services/reader_rich_typography.dart';
import 'package:wild/services/reading_progress.dart';
import 'package:wild/sources/book_source.dart';
import 'package:wild/widgets/cached_image.dart';
import 'package:wild/widgets/reader_paper_view.dart';

import 'epub_flow_integration_test.dart' as local;
import 'paginated_reader_requests_test.dart' as fixture;
import 'support/epub_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('paper stays still until one completed horizontal gesture', (
    tester,
  ) async {
    final turns = <int>[];
    var taps = 0;
    const paper = ValueKey('static-paper');
    await tester.pumpWidget(MaterialApp(
      home: EInkReaderView(
        onTurn: turns.add,
        onTapUp: (_) => taps++,
        child: const ColoredBox(key: paper, color: Colors.white),
      ),
    ));
    final original = tester.getRect(find.byKey(paper));
    final drag = await tester.startGesture(original.center);
    await drag.moveBy(const Offset(-100, 0));
    await tester.pump(const Duration(milliseconds: 300));
    expect(turns, isEmpty);
    expect(tester.getRect(find.byKey(paper)), original);
    expect(find.byType(PageView), findsNothing);
    await drag.moveBy(const Offset(-180, 0));
    await tester.pump(const Duration(seconds: 1));
    expect(turns, isEmpty);
    await drag.up();
    await tester.pump();
    expect(turns, [1]);
    expect(taps, 0);

    await tester.drag(find.byKey(paper), const Offset(160, 0));
    await tester.pump();
    expect(turns, [1, -1]);
    await tester.tap(find.byKey(paper));
    expect(taps, 1);
  });

  testWidgets('short, vertical and cancelled gestures do not turn', (
    tester,
  ) async {
    final turns = <int>[];
    await tester.pumpWidget(MaterialApp(
      home: EInkReaderView(
        onTurn: turns.add,
        onTapUp: (_) {},
        child: const ColoredBox(color: Colors.white),
      ),
    ));
    final target = find.byType(EInkReaderView);
    await tester.drag(target, const Offset(-35, 0));
    await tester.drag(target, const Offset(0, -160));
    final cancelled = await tester.startGesture(tester.getCenter(target));
    await cancelled.moveBy(const Offset(-180, 0));
    await cancelled.cancel();
    await tester.pump();
    expect(turns, isEmpty);
    await tester.drag(target, const Offset(-160, 0));
    await tester.pump();
    expect(turns, [1], reason: 'Cancelled distance cannot leak into a new drag.');
  });

  testWidgets('static spread uses existing chapter-local position and history', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final saved = <ReadingProgress>[];
    final queue = ReadingProgressQueue(write: (value) async => saved.add(value));
    final cubit = fixture.reader(
      ({required aid, required cid}) async {
        final document = ReaderDocument([
          ReaderBlock(runs: [ReaderRun('fixture chapter $cid')]),
        ]);
        return SourceChapter(document.content, document: document);
      },
      queue,
      bookId: local.bookId,
      chapterVolumes: local.volumes,
    );
    await cubit.loadChapter();
    await tester.pumpWidget(MaterialApp(
      home: BlocProvider.value(
        value: cubit,
        child: BlocBuilder<ReaderCubit, ReaderState>(
          builder: (context, state) {
            final loaded = state as ReaderLoaded;
            return EInkReaderView(
              onTapUp: (_) => cubit.toggleControls(),
              onTurn: (direction) {
                final current = cubit.state as ReaderLoaded;
                final view = current.layout.viewIndex(current.currentPageIndex);
                cubit.onPageChanged(current.layout.firstPage(view + direction));
              },
              child: ReaderPaperView(
                pages: loaded.pages,
                viewIndex: loaded.layout.viewIndex(loaded.currentPageIndex),
                layout: loaded.layout,
                chapterTitle: loaded.title,
                source: SourceId.localEpub,
                textStyle: const TextStyle(fontSize: 20, color: Colors.black),
                paragraphSpacing: 8,
                highContrast: true,
              ),
            );
          },
        ),
      ),
    ));
    expect((cubit.state as ReaderLoaded).layout.isSpread, isTrue);
    expect(find.byKey(const ValueKey('reader-leaf-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('reader-leaf-1')), findsOneWidget);
    await tester.drag(find.byType(EInkReaderView), const Offset(-200, 0));
    await tester.pump();
    await queue.flush();
    expect((cubit.state as ReaderLoaded).currentPageIndex, 2);
    expect(find.byKey(const ValueKey('reader-leaf-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('reader-leaf-3')), findsOneWidget);
    expect(saved.last.chapterId, 'c');
    expect(saved.last.page, 0);
    expect(saved.last.position!.textOffset, 0);
    expect(find.byType(PageView), findsNothing);
    await tester.tap(find.byType(EInkReaderView));
    await tester.pump();
    expect((cubit.state as ReaderLoaded).showControls, isTrue);
    expect((cubit.state as ReaderLoaded).currentPageIndex, 2);
    await tester.pumpWidget(const SizedBox());
    await cubit.close();
  });

  test('high contrast changes paint while preserving rich layout metrics', () {
    final block = ReaderBlock(
      runs: const [
        ReaderRun(
          'A colored, underlined paragraph that wraps over several lines. ',
          style: ReaderInlineStyle(
            color: 0xff6688aa,
            background: 0xff102030,
            bold: true,
            underline: true,
            scale: 1.2,
          ),
        ),
      ],
      style: const ReaderBlockStyle(
        indent: ReaderLength(em: 2),
        marginLeft: ReaderLength(em: 1),
        box: ReaderBoxStyle(
          background: 0xff102030,
          paddingTop: ReaderLength(em: .5),
          paddingLeft: ReaderLength(em: .5),
        ),
      ),
    );
    final fragment = model.ReaderFragment(
      block: block,
      start: 0,
      end: block.text.length,
      first: true,
      last: true,
    );
    ReaderParagraphLayout make(bool highContrast) => ReaderParagraphLayout(
      fragment: fragment,
      baseStyle: const TextStyle(fontSize: 20, height: 1.4, color: Colors.black),
      width: 240,
      textScaler: TextScaler.linear(1.1),
      highContrast: highContrast,
    );
    final normal = make(false), eink = make(true);
    expect(eink.height, normal.height);
    expect(eink.left, normal.left);
    expect(eink.painter.size, normal.painter.size);
    expect(eink.painter.computeLineMetrics().length,
        normal.painter.computeLineMetrics().length);
    final normalRun = (normal.painter.text! as TextSpan)
        .children!.whereType<TextSpan>().single;
    final einkRun = (eink.painter.text! as TextSpan)
        .children!.whereType<TextSpan>().single;
    expect(normalRun.style!.color, const Color(0xff6688aa));
    expect(einkRun.style!.color, Colors.black);
    expect(einkRun.style!.backgroundColor, Colors.white);
    expect(einkRun.style!.fontSize, normalRun.style!.fontSize);
    expect(einkRun.style!.decoration, normalRun.style!.decoration);
    normal.dispose();
    eink.dispose();
  });

  testWidgets('two turns before a build advance two committed spreads', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final saved = <ReadingProgress>[];
    final queue = ReadingProgressQueue(write: (value) async => saved.add(value));
    final cubit = fixture.reader(
      ({required aid, required cid}) async =>
          SourceChapter('A long fixture paragraph for rapid hardware turns. ' * 800),
      queue,
    );
    await cubit.loadChapter();
    expect((cubit.state as ReaderLoaded).pages.length, greaterThan(5));
    expect((cubit.state as ReaderLoaded).layout.isSpread, isTrue);
    await tester.pumpWidget(MaterialApp(
      home: EInkReaderView(
        onTapUp: (_) {},
        onTurn: (direction) {
          // Hardware events can be delivered together, before BlocBuilder has
          // copied the state into its widget. Use the committed cubit position.
          final current = cubit.state as ReaderLoaded;
          final view = current.layout.viewIndex(current.currentPageIndex);
          cubit.onPageChanged(current.layout.firstPage(view + direction));
        },
        child: const ColoredBox(color: Colors.white),
      ),
    ));
    final input = tester.widget<EInkReaderView>(find.byType(EInkReaderView));
    input.onTurn(1);
    input.onTurn(1);
    expect((cubit.state as ReaderLoaded).currentPageIndex, 4);
    await queue.flush();
    expect(saved.last.page, 4);
    await tester.pumpWidget(const SizedBox());
    await cubit.close();
  });

  test('static images keep source ownership and separate decoded cache keys', () {
    final normal = CachedImageProvider('https://example.invalid/book.gif',
        source: SourceId.bili, scale: 2);
    final still = normal.firstFrameOnly();
    expect(still, isNot(normal));
    expect(still.source, SourceId.bili);
    expect(still.scale, 2);
    expect(still.url, normal.url);
    expect(still.firstFrameOnly(), same(still));
    final cache = <CachedImageProvider, String>{normal: 'animated', still: 'first'};
    expect(cache.length, 2);
    expect(cache[normal.firstFrameOnly()], 'first');
  });

  testWidgets('static decoder requests one frame and disposes the codec', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final sourceCodec = await ui.instantiateImageCodec(epubFixturePng());
        final sourceFrame = await sourceCodec.getNextFrame();
        final codec = _CountingCodec(sourceFrame.image);
        sourceCodec.dispose();
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        String? referer;
        server.listen((request) async {
          referer = request.headers.value(HttpHeaders.refererHeader);
          request.response.add(epubFixturePng());
          await request.response.close();
        });
        final provider = CachedImageProvider(
          'http://127.0.0.1:${server.port}/fixture.gif',
          source: SourceId.bili,
          staticFrame: true,
        );
        final complete = Completer<void>();
        var emitted = 0;
        final stream = provider.loadImage(provider, (
          buffer, {cacheWidth, cacheHeight, allowUpscaling = false}
        ) async {
          buffer.dispose();
          return codec;
        });
        final listener = ImageStreamListener((info, synchronous) {
          emitted++;
          info.dispose();
          if (!complete.isCompleted) complete.complete();
        }, onError: (Object error, StackTrace? stack) {
          if (!complete.isCompleted) complete.completeError(error, stack);
        });
        stream.addListener(listener);
        try {
          await complete.future.timeout(const Duration(seconds: 5));
          await Future<void>.delayed(const Duration(milliseconds: 150));
          expect(emitted, 1);
          expect(codec.framesRequested, 1);
          expect(codec.disposed, isTrue);
          expect(referer, 'https://www.bilinovel.net/');
          expect(stream, isA<OneFrameImageStreamCompleter>());
        } finally {
          stream.removeListener(listener);
          sourceFrame.image.dispose();
          await server.close(force: true);
        }
      }, _RealHttpOverrides());
    });
  });
}

class _RealHttpOverrides extends HttpOverrides {}

class _CountingCodec implements ui.Codec {
  _CountingCodec(this.image);
  final ui.Image image;
  var framesRequested = 0;
  var disposed = false;
  @override
  int get frameCount => 3;
  @override
  int get repetitionCount => -1;
  @override
  Future<ui.FrameInfo> getNextFrame() async {
    framesRequested++;
    return _Frame(image.clone());
  }
  @override
  void dispose() => disposed = true;
}

class _Frame implements ui.FrameInfo {
  _Frame(this.image);
  @override
  final ui.Image image;
  @override
  Duration get duration => const Duration(milliseconds: 20);
}
