import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wild/models/reader_page.dart' as model;
import 'package:wild/pages/novel/reader_cubit.dart';
import 'package:wild/pages/novel/theme_cubit.dart';
import 'package:wild/services/epub/epub_css_reader.dart';
import 'package:wild/services/epub/epub_models.dart';
import 'package:wild/services/epub/local_epub_library.dart';

import 'support/epub_fixture.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('litetale/epub_pages');
  final messenger = binding.defaultBinaryMessenger;
  final library = LocalEpubLibrary(useIsolates: false);
  late Directory directory;
  late LocalEpubBook book;
  final readers = <EpubCssReader>[];
  final prepares = <Map<dynamic, dynamic>>[];
  final captureIds = <String>[];
  final theme = ReaderTheme(
    themeMode: ReaderThemeMode.light,
    lightBackgroundColor: const Color(0xffe5dccb),
    lightTextColor: const Color(0xff345678),
    darkBackgroundColor: const Color(0xff123456),
    darkTextColor: const Color(0xffabcdef),
  );

  setUp(() async {
    binding.platformDispatcher.views.first.physicalSize = const Size(500, 800);
    binding.platformDispatcher.views.first.devicePixelRatio = 1;
    directory = await Directory.systemTemp.createTemp('eink_epub_fixture_');
    await library.initialize(directory.path);
    book = (await library.importFile(
      XFile.fromData(buildEpubFixture(), path: 'eink_fixture.epub'),
    )).book;
    prepares.clear();
    captureIds.clear();
    readers.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'prepare') {
        prepares.add(Map.of(call.arguments as Map));
        return {
          'count': 2,
          'textLength': 8,
          'text': 'abcdefgh',
          'ranges': [
            {'start': 0, 'end': 4},
            {'start': 4, 'end': 8},
          ],
        };
      }
      if (call.method == 'capture') {
        captureIds.add(call.arguments['id'] as String);
        return epubFixturePng();
      }
      return null;
    });
  });

  tearDown(() async {
    for (final reader in readers) {
      reader.close();
    }
    await EpubCssReader.clearUnusedCache();
    messenger.setMockMethodCallHandler(channel, null);
    // Remove only the explicitly created fixture through the library's owned
    // book operation; no recursive directory deletion is used by this test.
    if (library.contains(book.id)) await library.remove(book.id);
    await Directory('${directory.path}/local_epub').delete();
    await directory.delete();
    binding.platformDispatcher.views.first.reset();
    PaintingBinding.instance.imageCache.clear();
  });

  Future<List<model.ReaderPage>> open({bool eink = false}) async {
    final reader = EpubCssReader(library: library);
    readers.add(reader);
    return reader.paginate(
      book: book.id,
      chapter: book.chapterId(0),
      content: 'abcdefgh',
      options: {
        'width': 500.0,
        'height': 800.0,
        'fontSize': 20.0,
        'lineHeight': 1.4,
        'paragraphGap': 8.0,
        'contentWidth': 468.0,
        'contentHeight': 688.0,
        ...readerEpubPaintOptions(
          theme: theme,
          brightness: Brightness.light,
          eink: eink,
        ),
      },
    );
  }

  test('real reader recipe omits disabled option and retains normal cache', () async {
    final original = await open();
    final first = original.first.cssPage!;
    await first.read();
    final before = Map<Object?, Object?>.from(prepares.single['options'] as Map);
    expect(before.containsKey('eink'), isFalse);
    expect(before['paper'], '#e5dccb');
    expect(before['ink'], '#345678');
    final explicitOff = await open(eink: false);
    final off = explicitOff.first.cssPage!;
    expect(off.key, first.key);
    await off.read();
    expect(prepares, hasLength(1));
    expect(captureIds.toSet(), hasLength(1));
  });

  test('enabling isolates EPUB pages; disabling restores recipe and anchors', () async {
    final normal = await open();
    final original = normal.first.cssPage!;
    await original.read();
    final oldOptions = Map<Object?, Object?>.from(prepares.first['options'] as Map);
    final eink = await open(eink: true);
    final highContrast = eink.first.cssPage!;
    await highContrast.read();
    final einkOptions = Map<Object?, Object?>.from(prepares.last['options'] as Map);
    expect(einkOptions['eink'], isTrue);
    expect(einkOptions['paper'], '#ffffff');
    expect(einkOptions['ink'], '#000000');
    expect(highContrast.key, isNot(original.key));
    expect(eink[1].cssPage!.domStart, normal[1].cssPage!.domStart);
    expect(eink[1].cssPage!.domEnd, normal[1].cssPage!.domEnd);
    for (final key in ['fontSize', 'lineHeight', 'paragraphGap', 'contentWidth', 'contentHeight']) {
      expect(einkOptions[key], oldOptions[key], reason: '$key is not a display color');
    }
    expect(theme.lightBackgroundColor, const Color(0xffe5dccb));
    expect(theme.lightTextColor, const Color(0xff345678));

    final restored = await open();
    expect(restored.first.cssPage!.key, original.key);
    expect(restored[1].cssPage!.domStart, normal[1].cssPage!.domStart);
    expect(prepares, hasLength(2));
    expect(captureIds.toSet(), hasLength(2));
  });

  test('executed EPUB style branch preserves artwork and changes only paint', () async {
    ProcessResult result;
    try {
      result = await Process.run('node', [
        '-e', einkStyleHarness,
        File('lib/assets/epub_page_engine.js').absolute.path,
      ]);
    } on ProcessException {
      markTestSkipped('Node is unavailable; run the browser style check separately.');
      return;
    }
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, contains('EPUB high contrast behavior passed'));
  });
}

// This executes the production function with an instrumented DOM. It checks
// mutation boundaries, not browser rasterization; device visual QA is separate.
const einkStyleHarness = r'''
const fs = require('node:fs');
const assert = require('node:assert/strict');
const source = fs.readFileSync(process.argv[1], 'utf8');
const start = source.indexOf('      const applyEink = doc => {');
const end = source.indexOf('      const applyStyle = doc => {', start);
assert(start >= 0 && end > start, 'Production style function must exist');
const factory = new Function('options', source.slice(start, end) + ';return applyEink;');
const make = () => {
  const element = values => ({
    values: {...values},
    writes: [],
    style: {setProperty(name, value, priority) {
      this.owner.writes.push([name,value,priority]);
      this.owner.values[name] = value;
    }},
  });
  const text = element({color:'#dddddd','background-color':'#222222','font-size':'19px'});
  const svg = element({color:'rgb(20, 30, 40)',fill:'rgb(50, 60, 70)',stroke:'none',
    '-webkit-text-fill-color':'rgb(20, 30, 40)','text-shadow':'none','text-decoration-color':'rgb(20, 30, 40)'});
  const image = element({opacity:'.7'});
  for (const item of [text,svg,image]) item.style.owner = item;
  const sheets = [];
  const selectors = [];
  const doc = {
    head: {append: sheet => sheets.push(sheet)},
    createElement: () => ({textContent:''}),
    defaultView: {getComputedStyle: el => ({getPropertyValue: name => el.values[name] || ''})},
    querySelectorAll: selector => {
      selectors.push(selector);
      if (selector === 'svg') return [svg];
      // The instrumented document explicitly rejects a selector that would
      // paint SVG descendants or bitmap elements in the text pass.
      assert(selector.includes(':not(svg)') && selector.includes(':not(svg *)'));
      assert(selector.includes(':not(img)'));
      return [text];
    },
  };
  return {doc,text,svg,image,sheets,selectors};
};
for (const options of [{}, {eink:false}, {eink:true,fixed:true}]) {
  const fixture = make();
  factory(options)(fixture.doc);
  assert.equal(fixture.selectors.length, 0);
  assert.equal(fixture.sheets.length, 0);
  assert.equal(fixture.text.writes.length, 0);
  assert.equal(fixture.svg.writes.length, 0);
}
const fixture = make();
const originalSvg = {...fixture.svg.values};
factory({eink:true,fixed:false})(fixture.doc);
assert.equal(fixture.text.values.color, '#000');
assert.equal(fixture.text.values['background-color'], '#fff');
assert.equal(fixture.text.values['font-size'], '19px');
assert.deepEqual(fixture.svg.values, originalSvg);
assert.equal(fixture.image.writes.length, 0);
assert.equal(fixture.sheets.length, 1);
const allowed = new Set(['color','-webkit-text-fill-color','background-color','border-color','text-shadow','text-decoration-color']);
assert(fixture.text.writes.every(([name,,priority]) => allowed.has(name) && priority === 'important'));
const styleCount = fixture.sheets.length;
factory({eink:true,fixed:false})(fixture.doc);
assert.equal(fixture.sheets.length, styleCount, 'applyEink must be idempotent');
console.log('EPUB high contrast behavior passed');
''';
