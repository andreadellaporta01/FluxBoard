import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../data/market_data.dart';
import 'painters.dart';
import 'frame_stats.dart';

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard>
    with SingleTickerProviderStateMixin {
  final MarketData _data = MarketData(loadMultiplier: 6);
  final FrameStats _stats = FrameStats();
  final ValueNotifier<int> _tick = ValueNotifier<int>(0);
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  bool _running = true;

  static const bool _isWasm = bool.fromEnvironment('dart.tool.dart2wasm');

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    if (!_running) return;
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    _data.tick(dt.clamp(0.0, 0.05));
    _tick.value++;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _stats.dispose();
    _tick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E17),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _header(),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 3, child: _leftColumn()),
                      const SizedBox(width: 12),
                      Expanded(flex: 2, child: _table()),
                    ],
                  ),
                ),
              ],
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: GlowPainter(_data, _tick)),
              ),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: FrameOverlay(
                stats: _stats,
                rendererLabel: _isWasm ? 'WASM · SKWASM' : 'JS · CANVASKIT',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          const Text('FluxBoard',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5)),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0x221CE8B5),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text('LIVE',
                style: TextStyle(
                    color: Color(0xFF1CE8B5),
                    fontSize: 11,
                    fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 24),
          _loadControl(),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _loadControl() {
    return Row(
      children: [
        IconButton(
          onPressed: () => setState(() => _running = !_running),
          icon: Icon(_running ? Icons.pause : Icons.play_arrow,
              color: Colors.white70),
          tooltip: 'Pause/resume the feed',
        ),
        const Text('Load', style: TextStyle(color: Colors.white54)),
        SizedBox(
          width: 160,
          child: Slider(
            value: _data.loadMultiplier.toDouble(),
            min: 1,
            max: 40,
            divisions: 39,
            label: '${_data.loadMultiplier}x',
            activeColor: const Color(0xFF1CE8B5),
            onChanged: (v) => setState(() => _data.loadMultiplier = v.round()),
          ),
        ),
        Text('${_data.loadMultiplier}x',
            style: const TextStyle(
                color: Colors.white70, fontFamily: 'monospace')),
      ],
    );
  }

  Widget _leftColumn() {
    return Column(
      children: [
        Expanded(flex: 3, child: _panel('AURX / USD · 1m', _candles())),
        const SizedBox(height: 12),
        Expanded(flex: 2, child: _panel('Sector correlation', _heatmap())),
      ],
    );
  }

  Widget _panel(String title, Widget child) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0E1420),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _candles() => CustomPaint(
        painter: CandlestickPainter(_data, _tick),
        size: Size.infinite,
      );

  Widget _heatmap() => CustomPaint(
        painter: HeatmapPainter(_data, _tick),
        size: Size.infinite,
      );

  Widget _table() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0E1420),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      padding: const EdgeInsets.all(6),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: const [
                Expanded(flex: 3, child: _Head('SYMBOL')),
                Expanded(flex: 2, child: _Head('PRICE', right: true)),
                Expanded(flex: 2, child: _Head('CHG%', right: true)),
                Expanded(flex: 3, child: _Head('TREND', right: true)),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0x14FFFFFF)),
          Expanded(
            child: AnimatedBuilder(
              animation: _tick,
              builder: (context, _) {
                return ListView.builder(
                  itemCount: MarketData.instrumentCount,
                  itemExtent: 34,
                  itemBuilder: (context, i) => _row(_data.instruments[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(Instrument inst) {
    final rising = inst.changePct >= 0;
    final col = rising ? const Color(0xFF1CE8B5) : const Color(0xFFFF5C7A);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(inst.symbol,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontFamily: 'monospace')),
          ),
          Expanded(
            flex: 2,
            child: Text(inst.price.toStringAsFixed(2),
                textAlign: TextAlign.right,
                style: const TextStyle(
                    color: Colors.white, fontSize: 13, fontFamily: 'monospace')),
          ),
          Expanded(
            flex: 2,
            child: Text(
                '${rising ? '+' : ''}${inst.changePct.toStringAsFixed(2)}',
                textAlign: TextAlign.right,
                style: TextStyle(
                    color: col, fontSize: 13, fontFamily: 'monospace')),
          ),
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.only(left: 10),
              child: CustomPaint(
                painter: SparklinePainter(inst.spark, rising),
                size: Size.infinite,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Head extends StatelessWidget {
  const _Head(this.text, {this.right = false});
  final String text;
  final bool right;

  @override
  Widget build(BuildContext context) {
    return Text(text,
        textAlign: right ? TextAlign.right : TextAlign.left,
        style: const TextStyle(
            color: Colors.white38,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1));
  }
}
