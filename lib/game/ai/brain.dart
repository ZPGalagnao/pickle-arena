// PickleBrain: runs the two neural networks trained by training/train_ai.py.
//
// The weights live in assets/ai/pickle_brain.json. Inference is a plain
// matrix-vector product per layer, so no ML runtime is needed on the phone.
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

class DenseLayer {
  final int inputs, outputs;
  final Float64List w; // row-major [in][out]
  final Float64List b;
  final String act;

  DenseLayer(this.inputs, this.outputs, this.w, this.b, this.act);

  factory DenseLayer.fromJson(Map<String, dynamic> j) {
    final rows = (j['w'] as List).cast<List>();
    final nIn = rows.length;
    final nOut = rows.first.length;
    final w = Float64List(nIn * nOut);
    for (var i = 0; i < nIn; i++) {
      final r = rows[i];
      for (var o = 0; o < nOut; o++) {
        w[i * nOut + o] = (r[o] as num).toDouble();
      }
    }
    final b = Float64List.fromList(
        (j['b'] as List).map((e) => (e as num).toDouble()).toList());
    return DenseLayer(nIn, nOut, w, b, j['act'] as String);
  }

  Float64List forward(Float64List x) {
    final y = Float64List.fromList(b);
    for (var i = 0; i < inputs; i++) {
      final xi = x[i];
      if (xi == 0) continue;
      final base = i * outputs;
      for (var o = 0; o < outputs; o++) {
        y[o] += xi * w[base + o];
      }
    }
    switch (act) {
      case 'relu':
        for (var o = 0; o < outputs; o++) {
          if (y[o] < 0) y[o] = 0;
        }
      case 'sigmoid':
        for (var o = 0; o < outputs; o++) {
          y[o] = 1 / (1 + math.exp(-y[o]));
        }
      case 'softmax':
        var m = y[0];
        for (var o = 1; o < outputs; o++) {
          m = math.max(m, y[o]);
        }
        var s = 0.0;
        for (var o = 0; o < outputs; o++) {
          y[o] = math.exp(y[o] - m);
          s += y[o];
        }
        for (var o = 0; o < outputs; o++) {
          y[o] /= s;
        }
      default:
        break;
    }
    return y;
  }
}

Float64List _vec(dynamic l) => Float64List.fromList(
    (l as List).map((e) => (e as num).toDouble()).toList());

/// Output of the trajectory predictor for one query plane.
class PlanePrediction {
  final double x, z, t; // where/when the ball reaches the plane
  final double reach; // probability it gets there at all
  final List<double> bounces; // P(0 / 1 / 2+ bounces before the plane)
  final double bounceX, bounceY, bounceT; // next bounce
  const PlanePrediction(this.x, this.z, this.t, this.reach, this.bounces,
      this.bounceX, this.bounceY, this.bounceT);

  int get likelyBounces {
    var best = 0;
    for (var i = 1; i < 3; i++) {
      if (bounces[i] > bounces[best]) best = i;
    }
    return best;
  }
}

class PickleBrain {
  final Float64List pIn, pStd, planeMean, planeStd, bounceMean, bounceStd;
  final List<DenseLayer> trunk;
  final Map<String, DenseLayer> heads;
  final Float64List sIn, sStd;
  final List<DenseLayer> selector;
  final Map<String, dynamic> metrics;
  final Map<String, dynamic> selftest;

  PickleBrain._(
      this.pIn,
      this.pStd,
      this.planeMean,
      this.planeStd,
      this.bounceMean,
      this.bounceStd,
      this.trunk,
      this.heads,
      this.sIn,
      this.sStd,
      this.selector,
      this.metrics,
      this.selftest);

  static PickleBrain? _instance;
  static PickleBrain? get instance => _instance;

  static Future<PickleBrain> load() async {
    if (_instance != null) return _instance!;
    final raw = await rootBundle.loadString('assets/ai/pickle_brain.json');
    _instance = PickleBrain.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    return _instance!;
  }

  factory PickleBrain.fromJson(Map<String, dynamic> j) {
    final p = j['predictor'] as Map<String, dynamic>;
    final s = j['selector'] as Map<String, dynamic>;
    final heads = <String, DenseLayer>{};
    (p['heads'] as Map<String, dynamic>).forEach((k, v) {
      heads[k] = DenseLayer.fromJson(v as Map<String, dynamic>);
    });
    return PickleBrain._(
      _vec(p['in_mean']),
      _vec(p['in_std']),
      _vec(p['plane_mean']),
      _vec(p['plane_std']),
      _vec(p['bounce_mean']),
      _vec(p['bounce_std']),
      (p['trunk'] as List)
          .map((e) => DenseLayer.fromJson(e as Map<String, dynamic>))
          .toList(),
      heads,
      _vec(s['in_mean']),
      _vec(s['in_std']),
      (s['layers'] as List)
          .map((e) => DenseLayer.fromJson(e as Map<String, dynamic>))
          .toList(),
      (j['metrics'] as Map<String, dynamic>?) ?? const {},
      (j['selftest'] as Map<String, dynamic>?) ?? const {},
    );
  }

  /// Canonical frame: the AI stands on y < 0 and the ball comes from y > 0.
  PlanePrediction predict(double bx, double by, double bz, double vx,
      double vy, double vz, double planeY) {
    final raw = [bx, by, bz, vx, vy, vz, planeY];
    var h = Float64List(7);
    for (var i = 0; i < 7; i++) {
      h[i] = (raw[i] - pIn[i]) / pStd[i];
    }
    for (final l in trunk) {
      h = l.forward(h);
    }
    final plane = heads['plane']!.forward(h);
    final reach = heads['reach']!.forward(h)[0];
    final nb = heads['nb']!.forward(h);
    final bounce = heads['bounce']!.forward(h);
    return PlanePrediction(
      plane[0] * planeStd[0] + planeMean[0],
      plane[1] * planeStd[1] + planeMean[1],
      plane[2] * planeStd[2] + planeMean[2],
      reach,
      [nb[0], nb[1], nb[2]],
      bounce[0] * bounceStd[0] + bounceMean[0],
      bounce[1] * bounceStd[1] + bounceMean[1],
      bounce[2] * bounceStd[2] + bounceMean[2],
    );
  }

  /// Probabilities of the 9 shots (drive/soft/lob x left/centre/right).
  /// Features: hitX, hitY, hitZ, oppX, oppY, inSpeed, oppMustBounce, power, control.
  Float64List shotProbabilities(List<double> features) {
    var h = Float64List(features.length);
    for (var i = 0; i < features.length; i++) {
      h[i] = (features[i] - sIn[i]) / sStd[i];
    }
    for (final l in selector) {
      h = l.forward(h);
    }
    return h;
  }
}
