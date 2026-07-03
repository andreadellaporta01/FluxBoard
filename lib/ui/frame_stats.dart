import 'dart:collection';
import 'dart:ui' show FramePhase;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// build = UI/Dart thread (what dart2wasm speeds up vs dart2js).
const Color kBuildColor = Color(0xFFFFC24B);

/// raster = raster thread (what multithreaded Skwasm offloads off the main thread).
const Color kRasterColor = Color(0xFF1CE8B5);

typedef FrameSample = ({double build, double raster, int tsMicros});

/// Collects real frame timings. The HERO metric is measured FPS derived from
/// actual frame cadence (interval between vsyncs) — honest for both the
/// single-threaded CanvasKit path and multithreaded Skwasm, where build and
/// raster run in parallel and a build+raster sum would be misleading.
/// build/raster durations are kept as the diagnostic that explains the cause.
class FrameStats extends ChangeNotifier {
  FrameStats({this.window = 90}) {
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  final int window;
  final Queue<FrameSample> _frames = Queue<FrameSample>();

  List<FrameSample> get samples => _frames.toList(growable: false);

  double _avg(double Function(FrameSample) sel) =>
      _frames.isEmpty ? 0 : _frames.map(sel).reduce((a, b) => a + b) / _frames.length;

  double get avgBuild => _avg((f) => f.build);
  double get avgRaster => _avg((f) => f.raster);

  /// Time between consecutive frames, in ms — the true cadence.
  List<double> get intervalsMs {
    final f = _frames.toList();
    final out = <double>[];
    for (var i = 1; i < f.length; i++) {
      final d = (f[i].tsMicros - f[i - 1].tsMicros) / 1000.0;
      if (d > 0 && d < 1000) out.add(d);
    }
    return out;
  }

  double get _avgIntervalMs {
    final iv = intervalsMs;
    if (iv.isEmpty) return 0;
    return iv.reduce((a, b) => a + b) / iv.length;
  }

  /// Measured refresh period (fastest observed interval), clamped to a sane
  /// range so it self-calibrates to 60Hz / 120Hz displays.
  double get refreshMs {
    final iv = intervalsMs;
    if (iv.isEmpty) return 1000 / 60;
    return iv.reduce((a, b) => a < b ? a : b).clamp(6.0, 1000 / 60);
  }

  double get fps => _avgIntervalMs <= 0 ? 0 : 1000.0 / _avgIntervalMs;
  double get targetFps => 1000.0 / refreshMs;

  /// Dropped frames: intervals notably longer than one refresh period.
  int get jankCount =>
      intervalsMs.where((d) => d > refreshMs * 1.5).length;

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      _frames.add((
        build: t.buildDuration.inMicroseconds / 1000.0,
        raster: t.rasterDuration.inMicroseconds / 1000.0,
        tsMicros: t.timestampInMicroseconds(FramePhase.vsyncStart),
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
        final fps = stats.fps;
        final ratio = stats.targetFps <= 0 ? 1.0 : fps / stats.targetFps;
        final color = ratio >= 0.9
            ? const Color(0xFF1CE8B5)
            : ratio >= 0.6
                ? const Color(0xFFFFC24B)
                : const Color(0xFFFF5252);
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
                  Flexible(
                    child: Text(rendererLabel,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.clip,
                        style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontFamily: 'monospace',
                            letterSpacing: 1)),
                  ),
                  const SizedBox(width: 8),
                  Text('${stats.jankCount} dropped',
                      style: TextStyle(
                          color: stats.jankCount > 0 ? color : Colors.white38,
                          fontSize: 12,
                          fontFamily: 'monospace')),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(fps.toStringAsFixed(0),
                      style: TextStyle(
                          color: color,
                          fontSize: 34,
                          height: 1,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'monospace')),
                  const SizedBox(width: 4),
                  const Flexible(
                    child: Text('fps',
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.clip,
                        style: TextStyle(color: Colors.white54, fontSize: 13)),
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                          '${(1000 / (stats.fps <= 0 ? 1 : stats.fps)).toStringAsFixed(1)} ms',
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
              Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Metric(
                          color: kBuildColor,
                          label: 'build',
                          value: stats.avgBuild),
                      const SizedBox(width: 16),
                      _Metric(
                          color: kRasterColor,
                          label: 'raster',
                          value: stats.avgRaster),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 44,
                child: CustomPaint(
                  size: const Size(double.infinity, 44),
                  painter: _IntervalGraphPainter(
                      stats.intervalsMs, stats.refreshMs),
                ),
              ),
              const SizedBox(height: 2),
              const Text('bars = frame interval · flat & low = smooth',
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
        Text('${value.toStringAsFixed(1)}ms',
            style: TextStyle(
                color: color, fontSize: 12, fontFamily: 'monospace')),
      ],
    );
  }
}

class _IntervalGraphPainter extends CustomPainter {
  _IntervalGraphPainter(this.intervals, this.refreshMs);
  final List<double> intervals;
  final double refreshMs;

  @override
  void paint(Canvas canvas, Size size) {
    const maxMs = 50.0;
    final budgetY = size.height - (refreshMs / maxMs) * size.height;

    canvas.drawLine(
      Offset(0, budgetY),
      Offset(size.width, budgetY),
      Paint()
        ..color = Colors.white24
        ..strokeWidth = 1,
    );

    if (intervals.isEmpty) return;
    final barW = size.width / intervals.length;
    final threshold = refreshMs * 1.35;
    for (var i = 0; i < intervals.length; i++) {
      final v = intervals[i].clamp(0.0, maxMs);
      final h = (v / maxMs) * size.height;
      final dropped = intervals[i] > threshold;
      canvas.drawRect(
        Rect.fromLTWH(i * barW, size.height - h, barW * 0.85, h),
        Paint()
          ..color = dropped ? const Color(0xFFFF5252) : const Color(0xFF1CE8B5),
      );
    }
  }

  @override
  bool shouldRepaint(_IntervalGraphPainter old) => true;
}
