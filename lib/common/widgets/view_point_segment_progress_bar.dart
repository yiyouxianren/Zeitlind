import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/gestures.dart' show TapGestureRecognizer;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show BoxHitTestEntry;

/// 仿 PiliPlus 的分段进度条：一条灰色底带 + 黑色分隔线 + 分段标题文字。
class ViewPointSegment {
  final double end;
  final String? title;
  final String? url;
  final int? from;
  final int? to;

  const ViewPointSegment({
    required this.end,
    this.title,
    this.url,
    this.from,
    this.to,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ViewPointSegment) return false;
    return end == other.end &&
        title == other.title &&
        url == other.url &&
        from == other.from &&
        to == other.to;
  }

  @override
  int get hashCode => Object.hash(end, title, url, from, to);
}

class ViewPointSegmentProgressBar extends LeafRenderObjectWidget {
  const ViewPointSegmentProgressBar({
    super.key,
    this.height = 3.5,
    required this.segments,
    this.onSeek,
  });

  final double height;
  final List<ViewPointSegment> segments;
  final ValueSetter<Duration>? onSeek;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderViewPointProgressBar(
      height: height,
      segments: segments,
      onSeek: onSeek,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderViewPointProgressBar renderObject,
  ) {
    renderObject
      ..height = height
      ..segments = segments
      ..onSeek = onSeek;
  }
}

class RenderViewPointProgressBar extends RenderBox {
  RenderViewPointProgressBar({
    required double height,
    required List<ViewPointSegment> segments,
    ValueSetter<Duration>? onSeek,
  })  : _height = height,
        _segments = segments,
        _onSeek = onSeek,
        _hitTestSelf = onSeek != null {
    if (onSeek != null) {
      _tapGestureRecognizer = TapGestureRecognizer()..onTapUp = _onTapUp;
    }
  }

  double _height;
  set height(double value) {
    if (_height == value) return;
    _height = value;
    markNeedsLayout();
  }

  List<ViewPointSegment> _segments;
  List<ViewPointSegment> get segments => _segments;
  set segments(List<ViewPointSegment> value) {
    if (listEquals(_segments, value)) return;
    _segments = value;
    markNeedsPaint();
  }

  ValueSetter<Duration>? _onSeek;
  set onSeek(ValueSetter<Duration>? value) {
    if (_onSeek == value) return;
    _onSeek = value;
  }

  TapGestureRecognizer? _tapGestureRecognizer;
  final bool _hitTestSelf;

  static const double _barHeight = 15.0;
  static const double _dividerWidth = 2.0;

  @override
  void performLayout() {
    size = constraints.constrainDimensions(constraints.maxWidth, _barHeight);
  }

  static ui.Paragraph _getParagraph(String title, double size) {
    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textDirection: TextDirection.ltr,
        strutStyle: ui.StrutStyle(leading: 0, height: 1, fontSize: size),
      ),
    )
      ..pushStyle(ui.TextStyle(
        color: Colors.white,
        fontSize: size,
        height: 1,
      ))
      ..addText(title);
    return builder.build()
      ..layout(const ui.ParagraphConstraints(width: double.infinity));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final size = this.size;
    final canvas = context.canvas;
    final paint = Paint()..style = PaintingStyle.fill;

    if (offset != Offset.zero) {
      canvas
        ..save()
        ..translate(offset.dx, offset.dy);
    }

    canvas.drawRect(
      Rect.fromLTRB(0, 0, size.width, _barHeight),
      paint..color = Colors.grey[600]!.withOpacity(0.45),
    );

    paint.color = Colors.black.withOpacity(0.5);

    double prevEnd = 0.0;
    for (final segment in segments) {
      final segmentEnd = segment.end * size.width;
      canvas.drawRect(
        Rect.fromLTRB(
          segmentEnd,
          0,
          segmentEnd + _dividerWidth,
          _barHeight,
        ),
        paint,
      );
      final title = segment.title;
      if (title != null && title.isNotEmpty) {
        final segmentWidth = segmentEnd - prevEnd;
        final paragraph = _getParagraph(title, 10);
        final textWidth = paragraph.maxIntrinsicWidth;
        final textHeight = paragraph.height;

        final isOverflow = textWidth > segmentWidth;
        Offset textOffset;
        if (isOverflow) {
          final scale = segmentWidth / textWidth;
          canvas
            ..save()
            ..translate(prevEnd, (_barHeight - textHeight * scale) / 2)
            ..scale(scale);
          textOffset = Offset.zero;
        } else {
          textOffset = Offset(
            (segmentWidth - textWidth) / 2 + prevEnd,
            (_barHeight - textHeight) / 2,
          );
        }
        canvas.drawParagraph(paragraph, textOffset);
        paragraph.dispose();
        if (isOverflow) {
          canvas.restore();
        }
      }
      prevEnd = segmentEnd + _dividerWidth;
    }
    if (offset != Offset.zero) canvas.restore();
  }

  @override
  bool hitTestSelf(Offset position) => _hitTestSelf;

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (event is PointerDownEvent) {
      _tapGestureRecognizer?.addPointer(event);
    }
  }

  @pragma('vm:notify-debugger-on-exception')
  void _onTapUp(TapUpDetails details) {
    try {
      final ratio = details.localPosition.dx / size.width;
      ViewPointSegment? target;
      for (final segment in segments) {
        if (segment.end >= ratio) {
          target = segment;
          break;
        }
      }
      target ??= segments.isEmpty ? null : segments.last;
      if (target?.from case final from?) {
        _onSeek?.call(Duration(seconds: from));
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _onSeek = null;
    _tapGestureRecognizer
      ?..onTapUp = null
      ..dispose();
    _tapGestureRecognizer = null;
    super.dispose();
  }
}
