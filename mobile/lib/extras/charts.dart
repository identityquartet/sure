import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/privacy_provider.dart';
import '../theme/sure_colors.dart';
import 'format.dart';

class ChartPoint {
  ChartPoint(this.date, this.value);
  final DateTime date;
  final double value;
}

/// Minimal line chart with touch scrubbing; no third-party dependency.
class LineChart extends StatefulWidget {
  const LineChart(this.points,
      {super.key, required this.currency, this.height = 180, this.color});
  final List<ChartPoint> points;
  final String currency;
  final double height;
  final Color? color;

  @override
  State<LineChart> createState() => _LineChartState();
}

class _LineChartState extends State<LineChart> {
  int? _touch;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    final hidden = context.watch<PrivacyProvider>().hidden;
    final pts = widget.points;
    if (pts.length < 2) {
      return SizedBox(
        height: widget.height,
        child: Center(
            child: Text('Not enough history yet', style: TextStyle(color: palette.textSubdued))),
      );
    }
    final first = pts.first.value, last = pts.last.value;
    final color = widget.color ?? (last >= first ? palette.success : palette.destructive);
    final sel = _touch == null ? null : pts[_touch!.clamp(0, pts.length - 1)];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        height: 20,
        child: sel == null
            ? null
            : Text(
                '${Fmt.day(sel.date)} · ${hidden ? '••••' : Fmt.money(sel.value, widget.currency)}',
                style: TextStyle(fontSize: 12, color: palette.textSecondary)),
      ),
      LayoutBuilder(builder: (context, c) {
        void update(Offset p) {
          final i = ((p.dx / c.maxWidth) * (pts.length - 1)).round().clamp(0, pts.length - 1);
          if (i != _touch) setState(() => _touch = i);
        }

        return GestureDetector(
          onHorizontalDragStart: (d) => update(d.localPosition),
          onHorizontalDragUpdate: (d) => update(d.localPosition),
          onHorizontalDragEnd: (_) => setState(() => _touch = null),
          onTapDown: (d) => update(d.localPosition),
          onTapUp: (_) => setState(() => _touch = null),
          child: CustomPaint(
            size: Size(c.maxWidth, widget.height),
            painter: _LinePainter(pts, color, palette.borderSecondary, _touch),
          ),
        );
      }),
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(children: [
          Text(Fmt.day(pts.first.date, pattern: 'd MMM yy'),
              style: TextStyle(fontSize: 11, color: palette.textSubdued)),
          const Spacer(),
          Text(Fmt.day(pts.last.date, pattern: 'd MMM yy'),
              style: TextStyle(fontSize: 11, color: palette.textSubdued)),
        ]),
      ),
    ]);
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.pts, this.color, this.grid, this.touch);
  final List<ChartPoint> pts;
  final Color color;
  final Color grid;
  final int? touch;

  @override
  void paint(Canvas canvas, Size size) {
    var lo = pts.map((p) => p.value).reduce(math.min);
    var hi = pts.map((p) => p.value).reduce(math.max);
    if (hi == lo) {
      hi += 1;
      lo -= 1;
    }
    final pad = (hi - lo) * 0.08;
    lo -= pad;
    hi += pad;
    Offset at(int i) => Offset(size.width * i / (pts.length - 1),
        size.height - (pts[i].value - lo) / (hi - lo) * size.height);

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var g = 0; g <= 3; g++) {
      final y = size.height * g / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < pts.length; i++) {
      final p = at(i);
      path.lineTo(p.dx, p.dy);
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0.25), color.withValues(alpha: 0.0)],
          ).createShader(Offset.zero & size));
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round);
    if (touch != null) {
      final p = at(touch!.clamp(0, pts.length - 1));
      canvas.drawLine(Offset(p.dx, 0), Offset(p.dx, size.height),
          Paint()
            ..color = color.withValues(alpha: 0.5)
            ..strokeWidth = 1);
      canvas.drawCircle(p, 5, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) =>
      old.pts != pts || old.touch != touch || old.color != color;
}

/// Horizontal bar used for category comparisons.
class ShareBar extends StatelessWidget {
  const ShareBar({super.key, required this.fraction, this.color, this.marker});
  final double fraction;
  final double? marker;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      return SizedBox(
        height: 8,
        child: Stack(children: [
          Container(
              decoration: BoxDecoration(
                  color: palette.surfaceInset, borderRadius: BorderRadius.circular(4))),
          Container(
            width: w * fraction.clamp(0, 1),
            decoration: BoxDecoration(
                color: color ?? palette.textPrimary, borderRadius: BorderRadius.circular(4)),
          ),
          if (marker != null)
            Positioned(
              left: (w * marker!.clamp(0, 1)) - 1,
              top: -2,
              bottom: -2,
              child: Container(width: 2, color: palette.textPrimary),
            ),
        ]),
      );
    });
  }
}
