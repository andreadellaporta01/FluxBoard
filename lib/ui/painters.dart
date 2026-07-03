import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../data/market_data.dart';

const _up = Color(0xFF1CE8B5);
const _down = Color(0xFFFF5C7A);
const _grid = Color(0x1AFFFFFF);
const _ma = Color(0xFFFFC24B);

/// Fixed ambient glow — purely decorative. The load knob drives CPU (tick),
/// not this layer, because on Flutter Web blur rasterization is GPU-cheap and
/// doesn't register as measurable raster cost.
class GlowPainter extends CustomPainter {
  GlowPainter(this.data, Listenable repaint) : super(repaint: repaint);
  final MarketData data;

  @override
  void paint(Canvas canvas, Size size) {
    const n = 40;
    final t = data.animPhase;
    for (var i = 0; i < n; i++) {
      final a = i * 0.7 + t;
      final x = (0.5 + 0.46 * math.sin(a * 1.13)) * size.width;
      final y = (0.5 + 0.46 * math.cos(a * 0.91)) * size.height;
      final r = 44.0 + 22.0 * math.sin(a * 2.1);
      final paint = Paint()
        ..color = (i.isEven ? _up : _ma).withValues(alpha: 0.06)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  @override
  bool shouldRepaint(GlowPainter old) => true;
}

class CandlestickPainter extends CustomPainter {
  CandlestickPainter(this.data, Listenable repaint) : super(repaint: repaint);
  final MarketData data;

  @override
  void paint(Canvas canvas, Size size) {
    final candles = data.candles;
    if (candles.isEmpty) return;

    final volH = size.height * 0.22;
    final priceH = size.height - volH - 8;

    var lo = double.infinity, hi = -double.infinity, maxVol = 0.0;
    for (final c in candles) {
      lo = math.min(lo, c.low);
      hi = math.max(hi, c.high);
      maxVol = math.max(maxVol, c.volume);
    }
    final range = (hi - lo).clamp(1e-6, double.infinity);

    final gridPaint = Paint()
      ..color = _grid
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = priceH * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      final price = hi - range * i / 4;
      _label(canvas, price.toStringAsFixed(0), Offset(4, y + 2), 10,
          Colors.white38);
    }

    final slot = size.width / candles.length;
    final bodyW = slot * 0.62;

    double yFor(double p) => priceH * (1 - (p - lo) / range);

    for (var i = 0; i < candles.length; i++) {
      final c = candles[i];
      final cx = slot * i + slot / 2;
      final bull = c.close >= c.open;
      final col = bull ? _up : _down;

      final wick = Paint()
        ..color = col
        ..strokeWidth = 1.2;
      canvas.drawLine(Offset(cx, yFor(c.high)), Offset(cx, yFor(c.low)), wick);

      final top = yFor(math.max(c.open, c.close));
      final bot = yFor(math.min(c.open, c.close));
      final body = Paint()..color = col;
      canvas.drawRect(
        Rect.fromLTRB(cx - bodyW / 2, top, cx + bodyW / 2,
            math.max(bot, top + 1)),
        body,
      );

      final vh = (c.volume / maxVol) * volH;
      final vPaint = Paint()..color = col.withValues(alpha: 0.35);
      canvas.drawRect(
        Rect.fromLTWH(cx - bodyW / 2, size.height - vh, bodyW, vh),
        vPaint,
      );
    }

    final maPath = Path();
    for (var i = 0; i < data.movingAvg.length; i++) {
      final cx = slot * i + slot / 2;
      final y = yFor(data.movingAvg[i]);
      if (i == 0) {
        maPath.moveTo(cx, y);
      } else {
        maPath.lineTo(cx, y);
      }
    }
    canvas.drawPath(
      maPath,
      Paint()
        ..color = _ma
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
  }

  void _label(Canvas c, String t, Offset o, double s, Color col) {
    final tp = TextPainter(
      text: TextSpan(text: t, style: TextStyle(color: col, fontSize: s)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, o);
  }

  @override
  bool shouldRepaint(CandlestickPainter old) => true;
}

class HeatmapPainter extends CustomPainter {
  HeatmapPainter(this.data, Listenable repaint) : super(repaint: repaint);
  final MarketData data;

  @override
  void paint(Canvas canvas, Size size) {
    final cols = MarketData.heatCols, rows = MarketData.heatRows;
    final cw = size.width / cols;
    final ch = size.height / rows;
    final paint = Paint();
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final v = data.heat[r * cols + c];
        paint.color = _heatColor(v);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(c * cw + 1, r * ch + 1, cw - 2, ch - 2),
            const Radius.circular(2),
          ),
          paint,
        );
      }
    }
  }

  Color _heatColor(double v) {
    if (v < 0.5) {
      return Color.lerp(const Color(0xFF12324A), const Color(0xFF1CE8B5), v * 2)!;
    }
    return Color.lerp(const Color(0xFF1CE8B5), const Color(0xFFFFC24B), (v - 0.5) * 2)!;
  }

  @override
  bool shouldRepaint(HeatmapPainter old) => true;
}

class SparklinePainter extends CustomPainter {
  SparklinePainter(this.points, this.rising);
  final List<double> points;
  final bool rising;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    var lo = double.infinity, hi = -double.infinity;
    for (final p in points) {
      lo = math.min(lo, p);
      hi = math.max(hi, p);
    }
    final range = (hi - lo).clamp(1e-6, double.infinity);
    final dx = size.width / (points.length - 1);
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = dx * i;
      final y = size.height * (1 - (points[i] - lo) / range);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = rising ? _up : _down
        ..strokeWidth = 1.4
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(SparklinePainter old) => true;
}
