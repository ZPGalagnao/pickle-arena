import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../game/shot_planner.dart';
import 'theme.dart';

/// Floating joystick: touch anywhere in its area and drag.
/// Reports (x, y) in -1..1, y > 0 = pushing up (toward the net).
class FloatingJoystick extends StatefulWidget {
  final void Function(double x, double y) onChanged;
  final double radius;

  const FloatingJoystick({super.key, required this.onChanged, this.radius = 58});

  @override
  State<FloatingJoystick> createState() => _FloatingJoystickState();
}

class _FloatingJoystickState extends State<FloatingJoystick> {
  Offset? _origin;
  Offset _knob = Offset.zero;
  int? _pointer;

  void _update(Offset local) {
    final o = _origin!;
    var d = local - o;
    final r = widget.radius;
    if (d.distance > r) d = d / d.distance * r;
    setState(() => _knob = d);
    var x = d.dx / r, y = -d.dy / r;
    final m = math.sqrt(x * x + y * y);
    if (m < 0.12) {
      x = 0;
      y = 0;
    } else {
      // rescale so movement starts smoothly after the dead zone
      final k = ((m - 0.12) / 0.88) / m;
      x *= k;
      y *= k;
    }
    widget.onChanged(x, y);
  }

  void _end() {
    setState(() {
      _origin = null;
      _knob = Offset.zero;
      _pointer = null;
    });
    widget.onChanged(0, 0);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final rest = Offset(box.maxWidth / 2, box.maxHeight - widget.radius - 18);
      final origin = _origin ?? rest;
      return Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) {
          if (_pointer != null) return;
          _pointer = e.pointer;
          _origin = e.localPosition;
          _update(e.localPosition);
        },
        onPointerMove: (e) {
          if (e.pointer == _pointer) _update(e.localPosition);
        },
        onPointerUp: (e) {
          if (e.pointer == _pointer) _end();
        },
        onPointerCancel: (e) {
          if (e.pointer == _pointer) _end();
        },
        child: CustomPaint(
          painter: _JoyPainter(origin, _knob, widget.radius, _origin != null),
          size: Size(box.maxWidth, box.maxHeight),
        ),
      );
    });
  }
}

class _JoyPainter extends CustomPainter {
  final Offset origin, knob;
  final double r;
  final bool active;
  _JoyPainter(this.origin, this.knob, this.r, this.active);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(origin, r, Paint()..color = Colors.white.withValues(alpha: active ? 0.14 : 0.08));
    canvas.drawCircle(
        origin,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white.withValues(alpha: active ? 0.45 : 0.25));
    final arrows = Paint()..color = Colors.white.withValues(alpha: 0.3);
    for (var i = 0; i < 4; i++) {
      final a = i * math.pi / 2;
      final c = origin + Offset(math.cos(a), math.sin(a)) * (r - 12);
      final p = Path()
        ..moveTo(c.dx + math.cos(a) * 6, c.dy + math.sin(a) * 6)
        ..lineTo(c.dx + math.cos(a + 2.2) * 6, c.dy + math.sin(a + 2.2) * 6)
        ..lineTo(c.dx + math.cos(a - 2.2) * 6, c.dy + math.sin(a - 2.2) * 6)
        ..close();
      canvas.drawPath(p, arrows);
    }
    final k = origin + knob;
    canvas.drawCircle(k, r * 0.44, Paint()..color = const Color(0x55000000));
    canvas.drawCircle(
        k,
        r * 0.42,
        Paint()
          ..shader = RadialGradient(colors: [
            Colors.white.withValues(alpha: 0.95),
            AppColors.lime.withValues(alpha: 0.85),
          ]).createShader(Rect.fromCircle(center: k, radius: r * 0.42)));
  }

  @override
  bool shouldRepaint(covariant _JoyPainter old) =>
      old.origin != origin || old.knob != knob || old.active != active;
}

class ShotButtons extends StatelessWidget {
  final void Function(ShotKind kind) onShot;
  final bool serving;
  final bool mirrored;

  const ShotButtons({super.key, required this.onShot, this.serving = false, this.mirrored = false});

  @override
  Widget build(BuildContext context) {
    final drive = _ShotButton(
        label: serving ? 'POWER\nSERVE' : 'DRIVE',
        icon: Icons.flash_on_rounded,
        colors: const [AppColors.orange, Color(0xFFFF4D4D)],
        size: 92,
        onTap: () => onShot(ShotKind.drive));
    final dink = _ShotButton(
        label: serving ? 'SOFT\nSERVE' : 'DINK',
        icon: Icons.water_drop_rounded,
        colors: const [AppColors.lime, Color(0xFF7BE35A)],
        size: 74,
        onTap: () => onShot(ShotKind.soft));
    final lob = _ShotButton(
        label: serving ? 'LOB\nSERVE' : 'LOB',
        icon: Icons.north_east_rounded,
        colors: const [AppColors.blue, AppColors.purple],
        size: 66,
        onTap: () => onShot(ShotKind.lob));
    return SizedBox(
      width: 200,
      height: 190,
      child: Stack(
        children: [
          Positioned(right: mirrored ? null : 8, left: mirrored ? 8 : null, bottom: 14, child: drive),
          Positioned(right: mirrored ? null : 108, left: mirrored ? 108 : null, bottom: 6, child: dink),
          Positioned(right: mirrored ? null : 40, left: mirrored ? 40 : null, bottom: 112, child: lob),
        ],
      ),
    );
  }
}

class _ShotButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final List<Color> colors;
  final double size;
  final VoidCallback onTap;

  const _ShotButton(
      {required this.label, required this.icon, required this.colors, required this.size, required this.onTap});

  @override
  State<_ShotButton> createState() => _ShotButtonState();
}

class _ShotButtonState extends State<_ShotButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return Listener(
      onPointerDown: (_) {
        setState(() => _down = true);
        widget.onTap();
      },
      onPointerUp: (_) => setState(() => _down = false),
      onPointerCancel: (_) => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down ? 0.88 : 1,
        duration: const Duration(milliseconds: 70),
        child: Container(
          width: s,
          height: s,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: widget.colors.map((c) => c.withValues(alpha: 0.92)).toList()),
            border: Border.all(color: Colors.white.withValues(alpha: 0.7), width: 2.5),
            boxShadow: [
              BoxShadow(color: widget.colors.first.withValues(alpha: _down ? 0.7 : 0.4), blurRadius: _down ? 22 : 12),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.icon, color: AppColors.bg, size: s * 0.3),
              Text(widget.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: AppColors.bg, fontWeight: FontWeight.w900, fontSize: s * 0.13, height: 1.05)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tilt-to-move using the accelerometer. Neutral = how the phone is held
/// when the match starts (or when "calibrate" is pressed).
class TiltController {
  StreamSubscription<AccelerometerEvent>? _sub;
  double _x0 = 0, _y0 = 0;
  double _x = 0, _y = 0;
  bool _calibrated = false;
  double mx = 0, my = 0;

  void start() {
    _sub = accelerometerEventStream(samplingPeriod: SensorInterval.gameInterval).listen((e) {
      _x = _x * 0.6 + e.x * 0.4;
      _y = _y * 0.6 + e.y * 0.4;
      if (!_calibrated) {
        _x0 = _x;
        _y0 = _y;
        _calibrated = true;
      }
      double shape(double v) {
        final a = v.abs();
        if (a < 0.12) return 0;
        return v.sign * math.min(1.0, (a - 0.12) / 0.6);
      }

      mx = shape(-(_x - _x0) / 3.2);
      my = shape((_y0 - _y) / 3.2);
    }, onError: (_) {});
  }

  void calibrate() {
    _x0 = _x;
    _y0 = _y;
  }

  void dispose() => _sub?.cancel();
}
