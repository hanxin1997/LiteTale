import 'package:wild/eink/eink_policy.dart';
import 'package:wild/services/reader_images.dart';
import 'package:flutter/material.dart';
import 'package:wild/sources/book_source.dart';
import 'package:flutter/foundation.dart';
import 'dart:ui' as ui;

/// EPUB hotspots supply original image bytes without a cached inline frame.
/// Keep the original bytes for export and decode just the display frame.
class EInkMemoryImage extends MemoryImage {
  const EInkMemoryImage(super.bytes);

  @override
  ImageStreamCompleter loadImage(MemoryImage key, ImageDecoderCallback decode) {
    final codec = ui.ImmutableBuffer.fromUint8List(key.bytes).then(
      (buffer) => decode(buffer),
    );
    return OneFrameImageStreamCompleter(_firstFrame(codec, key.scale));
  }
}

Future<ImageInfo> _firstFrame(Future<ui.Codec> pending, double scale) async {
  final codec = await pending;
  try {
    final frame = await codec.getNextFrame();
    return ImageInfo(image: frame.image, scale: scale);
  } finally {
    codec.dispose();
  }
}

class CachedImageProvider extends ImageProvider<CachedImageProvider> {
  final String url;
  final double scale;
  final SourceId source;
  final int revision;
  final bool staticFrame;

  CachedImageProvider(
    this.url, {
    required this.source,
    this.scale = 1.0,
    this.staticFrame = false,
    int? revision,
  }) : revision = revision ?? sourceRevision.value;

  CachedImageProvider firstFrameOnly() => staticFrame ? this : CachedImageProvider(
    url, source: source, scale: scale, revision: revision, staticFrame: true,
  );

  @override
  ImageStreamCompleter loadImage(
    CachedImageProvider key,
    ImageDecoderCallback decode,
  ) {
    if (key.staticFrame) {
      // Decode through the same source-owned request path, but never schedule
      // subsequent GIF/WebP frames. The separate key prevents cache crossover.
      return OneFrameImageStreamCompleter(
        _firstFrame(_loadAsync(key, decode), key.scale),
      );
    }
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: key.scale,
    );
  }

  @override
  Future<CachedImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture(this);
  }

  Future<ui.Codec> _loadAsync(
    CachedImageProvider key,
    ImageDecoderCallback decode,
  ) async {
    assert(key == this);
    final ref = ReaderImageRef(source: source, url: url);
    final revision = key.revision;
    final repository = ReaderImageRepository.instance;
    final data = await repository.read(ref, revision: revision);
    try {
      return await decode(await ui.ImmutableBuffer.fromUint8List(data.bytes));
    } on Object {
      repository.invalidate(ref, revision: revision);
      rethrow;
    }
  }

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) return false;
    final CachedImageProvider typedOther = other as CachedImageProvider;
    return url == typedOther.url &&
        scale == typedOther.scale &&
        source == typedOther.source &&
        revision == typedOther.revision && staticFrame == typedOther.staticFrame;
  }

  @override
  int get hashCode => Object.hash(url, scale, source, revision, staticFrame);

  @override
  String toString() =>
      '$runtimeType(url: ${describeIdentity(url)}, scale: $scale)';
}

class CachedImage extends StatelessWidget {
  final String url;
  final SourceId source;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final int? cacheWidth;

  const CachedImage({
    super.key,
    required this.url,
    required this.source,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.cacheWidth,
  });

  @override
  Widget build(BuildContext context) {
    Widget image = Image(
      image: ResizeImage.resizeIfNeeded(
        cacheWidth,
        null,
        CachedImageProvider(
          url,
          source: source,
          staticFrame: einkEnabled(context),
        ),
      ),
      fit: fit,
      width: width,
      height: height,
      // Mipmapped filtering preserves detail when large covers are reduced.
      // Bicubic (high) filtering can alias when shrinking below half-size.
      filterQuality: FilterQuality.medium,
      frameBuilder:
          (context, child, frame, wasSynchronouslyLoaded) =>
              frame == null
                  ? ColoredBox(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: Center(
                      child: Icon(
                        Icons.image_outlined,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                  : child,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Icon(
            Icons.broken_image_outlined,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        );
      },
    );

    if (borderRadius != null) {
      image = ClipRRect(borderRadius: borderRadius!, child: image);
    }

    return image;
  }
}
