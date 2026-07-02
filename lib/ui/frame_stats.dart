import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// build = UI/Dart thread (what dart2wasm speeds up vs dart2js).
const Color kBuildColor = Color(0xFFFFC24B);

/// raster = raster thread (what multithreaded Skwasm offloads off the main thread).
const Color kRasterColor = Color(0xFF1CE8B5);

typedef FrameSample = ({double build, double raster});

/// Collects real frame timings from the engine, split into build (UI thread)
/// and raster (raster thread), and exposes a rolling window. The split is the
/// whole point: it shows on stage which cost dominates, so the JS-vs-Wasm
/// story is told with the right cause.
class FrameStats extends ChangeNotifier {
  FrameStats({this.window = 90}) {
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  final int window;
  final Queue<FrameSample> _frames = Queue<FrameSample>();

  static const double budgetMs = 1000.0 / 60.0; // 16.67ms = one 60fps frame

  List<FrameSample> get samples => _frames.toList(growable: false);

  double _avg(double Function(FrameSample) sel) =>
      _frames.isEmpty ? 0 : _frames.map(sel).reduce((a, b) => a + b) / _frames.length;

  double get avgBuild => _avg((f) => f.build);
  double get avgRaster => _avg((f) => f.raster);
  double get avgTotalMs => avgBuild + avgRaster;

  double get maxMs => _frames.isEmpty
      ? 0
      : _frames.map((f) => f.build + f.raster).reduce((a, b) => a > b ? a : b);

  double get fps => avgTotalMs <= 0 ? 0 : (1000.0 / avgTotalMs).clamp(0, 60);

  int get jankCount =>
      _frames.where((f) => f.build + f.raster > budgetMs).length;

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      _frames.add((
        build: t.buildDuration.inMicroseconds / 1000.0,
        raster: t.rasterDuration.inMicroseconds / 1000.0,
      ));
      while (_frames.length > window) {
        _frames.removeFirst();
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
  const FrameOverlay(
      {super.key, required this.stats, required this.rendererLabel});

  final FrameStats stats;
  final String rendererLabel;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: stats,
      builder: (context, _) {
        final total = stats.avgTotalMs;
        final over = total > FrameStats.budgetMs;
        final totalColor =
            over ? const Color(0xFFFF5252) : const Color(0xFF1CE8B5);
        return Container(
          width: 320,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          decoration: BoxDecoration(
            color: const Color(0xF20E1420),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: totalColor.withValues(alpha: 0.5)),
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
                          color: over ? totalColor : Colors.white38,
                          fontSize: 12,
                          fontFamily: 'monospace')),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(total.toStringAsFixed(1),
                      style: TextStyle(
                          color: totalColor,
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
              const SizedBox(height: 6),
              Row(
                children: [
                  _Metric(
                      color: kBuildColor, label: 'build', value: stats.avgBuild),
                  const SizedBox(width: 16),
                  _Metric(
                      color: kRasterColor,
                      label: 'raster',
                      value: stats.avgRaster),
                  const Spacer(),
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
              const Text('stacked build+raster · 16.7ms = 60fps',
                  style: TextStyle(color: Colors.white30, fontSize: 10)),
            ],
          ),
        );
      },
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(
      {required this.color, required this.label, required this.value});

  final Color color;
  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, color: color),
        const SizedBox(width: 5),
        Text(label,
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(width: 5),
        Text(value.toStringAsFixed(1),
            style: TextStyle(
                color: color, fontSize: 12, fontFamily: 'monospace')),
      ],
    );
  }
}

class _FrameGraphPainter extends CustomPainter {
  _FrameGraphPainter(this.samples);
  final List<FrameSample> samples;

  @override
  void paint(Canvas canvas, Size size) {
    const maxMs = 50.0;
    final budgetY = size.height - (FrameStats.budgetMs / maxMs) * size.height;

    canvas.drawLine(
      Offset(0, budgetY),
      Offset(size.width, budgetY),
      Paint()
        ..color = Colors.white24
        ..strokeWidth = 1,
    );

    if (samples.isEmpty) return;
    final barW = size.width / samples.length;
    final buildPaint = Paint()..color = kBuildColor;
    final rasterPaint = Paint()..color = kRasterColor;

    for (var i = 0; i < samples.length; i++) {
      final s = samples[i];
      final x = i * barW;
      final w = barW * 0.85;

      final buildH = (s.build.clamp(0.0, maxMs) / maxMs) * size.height;
      final rasterH = (s.raster.clamp(0.0, maxMs) / maxMs) * size.height;
      final clampedRasterH =
          (buildH + rasterH > size.height) ? size.height - buildH : rasterH;

      // build sits at the bottom, raster stacks on top.
      canvas.drawRect(
        Rect.fromLTWH(x, size.height - buildH, w, buildH),
        buildPaint,
      );
      canvas.drawRect(
        Rect.fromLTWH(x, size.height - buildH - clampedRasterH, w,
            clampedRasterH.clamp(0.0, size.height)),
        rasterPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_FrameGraphPainter old) => true;
}
