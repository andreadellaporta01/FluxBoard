import 'dart:math' as math;
import 'dart:typed_data';

class Candle {
  double open, high, low, close, volume;
  Candle(this.open, this.high, this.low, this.close, this.volume);
}

class Instrument {
  final String symbol;
  double price;
  double changePct;
  double volume;
  final List<double> spark;
  Instrument(this.symbol, this.price)
      : changePct = 0,
        volume = 0,
        spark = List<double>.filled(24, 0, growable: true);
}

/// In-place mutable market state. `tick()` does deliberately heavy,
/// allocation-y work every frame to stress the main thread and the GC —
/// this is the whole point of the demo.
class MarketData {
  MarketData({this.loadMultiplier = 3}) {
    _seedCandles();
    _seedHeat();
    _seedInstruments();
  }

  final math.Random _rng = math.Random(42);

  /// Bump to make each frame heavier (more CPU + more allocations).
  int loadMultiplier;

  // --- Candlestick series -------------------------------------------------
  static const int candleCount = 160;
  final List<Candle> candles = [];
  final List<double> movingAvg = [];
  double _lastClose = 220;

  void _seedCandles() {
    for (var i = 0; i < candleCount; i++) {
      _pushCandle();
    }
    _recomputeMovingAverage();
  }

  void _pushCandle() {
    final open = _lastClose;
    final drift = (_rng.nextDouble() - 0.48) * 6;
    final close = math.max(20.0, open + drift);
    final high = math.max(open, close) + _rng.nextDouble() * 3;
    final low = math.min(open, close) - _rng.nextDouble() * 3;
    final vol = 40 + _rng.nextDouble() * 100;
    candles.add(Candle(open, high, low, close, vol));
    if (candles.length > candleCount) candles.removeAt(0);
    _lastClose = close;
  }

  void _recomputeMovingAverage() {
    movingAvg.clear();
    const window = 14;
    for (var i = 0; i < candles.length; i++) {
      var sum = 0.0;
      final start = math.max(0, i - window + 1);
      for (var j = start; j <= i; j++) {
        sum += candles[j].close;
      }
      movingAvg.add(sum / (i - start + 1));
    }
  }

  // --- Heatmap ------------------------------------------------------------
  static const int heatCols = 48;
  static const int heatRows = 22;
  final Float64List heat = Float64List(heatCols * heatRows);

  void _seedHeat() => _recomputeHeat(0);

  void _recomputeHeat(double t) {
    for (var r = 0; r < heatRows; r++) {
      for (var c = 0; c < heatCols; c++) {
        final v = 0.5 +
            0.5 *
                math.sin(c * 0.35 + t * 1.7) *
                math.cos(r * 0.4 - t * 1.1) *
                math.sin((r + c) * 0.15 + t);
        heat[r * heatCols + c] = v.clamp(0.0, 1.0);
      }
    }
  }

  // --- Instrument table (5000 rows) --------------------------------------
  static const int instrumentCount = 5000;
  final List<Instrument> instruments = [];

  void _seedInstruments() {
    const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    for (var i = 0; i < instrumentCount; i++) {
      final s = StringBuffer();
      for (var k = 0; k < 4; k++) {
        s.write(letters[_rng.nextInt(letters.length)]);
      }
      final inst = Instrument('${s.toString()}$i', 50 + _rng.nextDouble() * 400);
      for (var j = 0; j < inst.spark.length; j++) {
        inst.spark[j] = inst.price + (_rng.nextDouble() - 0.5) * 20;
      }
      instruments.add(inst);
    }
  }

  // --- Per-frame update ---------------------------------------------------
  double _phase = 0;

  void tick(double dt) {
    _phase += dt;

    // Heavier every extra load unit: re-run the expensive passes N times.
    for (var pass = 0; pass < loadMultiplier; pass++) {
      _recomputeHeat(_phase);

      for (final inst in instruments) {
        final step = (_rng.nextDouble() - 0.5) * inst.price * 0.01;
        inst.price = math.max(1.0, inst.price + step);
        inst.changePct = step / inst.price * 100;
        inst.volume += _rng.nextDouble() * 5;
        // Allocation churn: shift the sparkline window every frame.
        inst.spark.removeAt(0);
        inst.spark.add(inst.price);
      }
    }

    _pushCandle();
    _recomputeMovingAverage();
  }
}
