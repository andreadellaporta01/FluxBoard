import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Collects real frame timings (build + raster) from the engine and exposes
/// a rolling window. This is the on-screen number the audience watches.
class FrameStats extends ChangeNotifier {
  FrameStats({this.window = 90}) {
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  final int window;
  final Queue<double> _frameMs = Queue<double>();

  static const double budgetMs = 1000.0 / 60.0; // 16.67ms = one 60fps frame

  List<double> get samples => _frameMs.toList(growable: false);

  double get avgMs =>
      _frameMs.isEmpty ? 0 : _frameMs.reduce((a, b) => a + b) / _frameMs.length;

  double get maxMs =>
      _frameMs.isEmpty ? 0 : _frameMs.reduce((a, b) => a > b ? a : b);

  double get fps => avgMs <= 0 ? 0 : (1000.0 / avgMs).clamp(0, 60);

  int get jankCount => _frameMs.where((m) => m > budgetMs).length;

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      _frameMs.add(t.totalSpan.inMicroseconds / 1000.0);
      while (_frameMs.length > window) {
        _frameMs.removeFirst();
      }
    }
    notifyListeners();
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    super.dispose();
  }
}

class FrameOverlay extends StatelessWidget {
  const FrameOverlay({super.key, required this.stats, required this.rendererLabel});

  final FrameStats stats;
  final String rendererLabel;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: stats,
      builder: (context, _) {
        final avg = stats.avgMs;
        final over = avg > FrameStats.budgetMs;
        final color = over ? const Color(0xFFFF5252) : const Color(0xFF1CE8B5);
        return Container(
          width: 320,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          decoration: BoxDecoration(
            color: const Color(0xF20E1420),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(rendererLabel,
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontFamily: 'monospace',
                          letterSpacing: 1)),
                  Text('${stats.jankCount} janky',
                      style: TextStyle(
                          color: over ? color : Colors.white38,
                          fontSize: 12,
                          fontFamily: 'monospace')),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(avg.toStringAsFixed(1),
                      style: TextStyle(
                          color: color,
                          fontSize: 34,
                          height: 1,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'monospace')),
                  const SizedBox(width: 4),
                  const Flexible(
                    child: Text('ms/frame',
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.clip,
                        style: TextStyle(color: Colors.white54, fontSize: 13)),
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text('${stats.fps.toStringAsFixed(0)} fps',
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.clip,
                          style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 16,
                              fontFamily: 'monospace')),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 44,
                child: CustomPaint(
                  size: const Size(double.infinity, 44),
                  painter: _FrameGraphPainter(stats.samples),
                ),
              ),
              const SizedBox(height: 2),
              const Text('16.7ms = 60fps budget',
                  style: TextStyle(color: Colors.white30, fontSize: 10)),
            ],
          ),
        );
      },
    );
  }
}

class _FrameGraphPainter extends CustomPainter {
  _FrameGraphPainter(this.samples);
  final List<double> samples;

  @override
  void paint(Canvas canvas, Size size) {
    const maxMs = 50.0;
    final budgetY =
        size.height - (FrameStats.budgetMs / maxMs) * size.height;

    final budgetPaint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;
    canvas.drawLine(
        Offset(0, budgetY), Offset(size.width, budgetY), budgetPaint);

    if (samples.isEmpty) return;
    final barW = size.width / samples.length;
    for (var i = 0; i < samples.length; i++) {
      final v = samples[i].clamp(0.0, maxMs);
      final h = (v / maxMs) * size.height;
      final over = samples[i] > FrameStats.budgetMs;
      final paint = Paint()
        ..color = over ? const Color(0xFFFF5252) : const Color(0xFF1CE8B5);
      canvas.drawRect(
        Rect.fromLTWH(i * barW, size.height - h, barW * 0.85, h),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_FrameGraphPainter old) => true;
}
