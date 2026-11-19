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
      // rescale so movement starts smoothly after the dead zone and
      // reaches full speed at 60% of the way out
      final k = ((m - 0.12) / 0.48).clamp(0.0, 1.0) / m;
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

/// POWER / SOFT / HIGH buttons plus the SPECIAL gauge button.
class ShotButtons extends StatelessWidget {
  final void Function(ShotKind kind) onShot;
  final VoidCallback onSpecial;
  final bool serving;
  final bool mirrored;
  final double meter; // 0..1 special charge
  final bool specialArmed;
  final Color specialColor;
  final String specialName;

  const ShotButtons({
    super.key,
    required this.onShot,
    required this.onSpecial,
    this.serving = false,
    this.mirrored = false,
    this.meter = 0,
    this.specialArmed = false,
    this.specialColor = AppColors.orange,
    this.specialName = 'SPECIAL',
  });

  @override
  Widget build(BuildContext context) {
    final power = _ShotButton(
        label: serving ? 'POWER\nSERVE' : 'POWER',
        icon: Icons.flash_on_rounded,
        colors: const [AppColors.orange, Color(0xFFFF4D4D)],
        size: 84,
        onTap: () => onShot(ShotKind.drive));
    final soft = _ShotButton(
        label: serving ? 'SOFT\nSERVE' : 'SOFT',
        icon: Icons.water_drop_rounded,
        colors: const [AppColors.lime, Color(0xFF7BE35A)],
        size: 70,
        onTap: () => onShot(ShotKind.soft));
    final high = _ShotButton(
        label: serving ? 'HIGH\nSERVE' : 'HIGH',
        icon: Icons.north_east_rounded,
        colors: const [AppColors.blue, AppColors.purple],
        size: 62,
        onTap: () => onShot(ShotKind.lob));
    final special = SpecialButton(
      meter: meter,
      armed: specialArmed,
      color: specialColor,
      name: specialName,
      onTap: onSpecial,
      enabled: !serving,
    );
    double? l(double v) => mirrored ? v : null;
    double? r(double v) => mirrored ? null : v;
    return SizedBox(
      width: 230,
      height: 200,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(right: r(6), left: l(6), bottom: 8, child: power),
          Positioned(right: r(98), left: l(98), bottom: 2, child: soft),
          Positioned(right: r(36), left: l(36), bottom: 102, child: high),
          Positioned(right: r(128), left: l(128), bottom: 86, child: special),
        ],
      ),
    );
  }
}

/// Round button whose ring fills up as the special meter charges.
class SpecialButton extends StatefulWidget {
  final double meter;
  final bool armed;
  final bool enabled;
  final Color color;
  final String name;
  final VoidCallback onTap;
  final double size;

  const SpecialButton({
    super.key,
    required this.meter,
    required this.armed,
    required this.color,
    required this.name,
    required this.onTap,
    this.enabled = true,
    this.size = 76,
  });

  @override
  State<SpecialButton> createState() => _SpecialButtonState();
}

class _SpecialButtonState extends State<SpecialButton> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = widget.meter >= 1;
    final s = widget.size;
    return Listener(
      onPointerDown: (_) {
        if (ready && widget.enabled) widget.onTap();
      },
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) {
          final glow = ready ? 0.4 + 0.6 * _pulse.value : 0.0;
          return SizedBox(
            width: s,
            height: s,
            child: CustomPaint(
              painter: _GaugePainter(widget.meter.clamp(0.0, 1.0), widget.color, glow, widget.armed),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(widget.armed ? Icons.local_fire_department_rounded : Icons.auto_awesome_rounded,
                        color: ready ? Colors.white : Colors.white54, size: s * 0.3),
                    Text(
                      widget.armed ? 'ARMED!' : (ready ? 'SPECIAL' : '${(widget.meter * 100).floor()}%'),
                      style: TextStyle(
                          color: ready ? Colors.white : Colors.white60,
                          fontWeight: FontWeight.w900,
                          fontSize: s * 0.13),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double value, glow;
  final Color color;
  final bool armed;
  _GaugePainter(this.value, this.color, this.glow, this.armed);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 4;
    if (glow > 0) {
      canvas.drawCircle(c, r + 8, Paint()..shader = RadialGradient(colors: [
            color.withValues(alpha: 0.7 * glow),
            color.withValues(alpha: 0),
          ]).createShader(Rect.fromCircle(center: c, radius: r + 10)));
    }
    canvas.drawCircle(c, r, Paint()..color = (armed ? color : const Color(0xCC0B1730)));
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..color = Colors.white24);
    canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        -math.pi / 2,
        math.pi * 2 * value,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round
          ..color = value >= 1 ? Color.lerp(color, Colors.white, 0.3 * glow)! : color);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      old.value != value || old.glow != glow || old.armed != armed || old.color != color;
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
