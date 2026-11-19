import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';

import '../game/render/character_painter.dart';
import '../game/shot_planner.dart';
import '../models/profile.dart';

/// Decodes face JPEGs once and keeps the ui.Image around.
class FaceCache {
  static final Map<int, ui.Image> _cache = {};
  static final Map<int, Future<ui.Image?>> _pending = {};

  static int _key(Uint8List b) => Object.hash(b.length, Object.hashAll(b.take(64)),
      Object.hashAll(b.skip(b.length > 128 ? b.length - 64 : 0)));

  static ui.Image? peek(Uint8List? bytes) => bytes == null ? null : _cache[_key(bytes)];

  static Future<ui.Image?> get(Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) return Future.value(null);
    final k = _key(bytes);
    final hit = _cache[k];
    if (hit != null) return Future.value(hit);
    return _pending[k] ??= () async {
      try {
        final codec = await ui.instantiateImageCodec(bytes, targetWidth: 256);
        final frame = await codec.getNextFrame();
        _cache[k] = frame.image;
        return frame.image;
      } catch (_) {
        return null;
      } finally {
        _pending.remove(k);
      }
    }();
  }
}

/// Round face avatar (photo or cartoon) with the player's jersey ring.
class FaceAvatar extends StatefulWidget {
  final PlayerProfile profile;
  final double size;
  final bool ring;

  const FaceAvatar({super.key, required this.profile, this.size = 56, this.ring = true});

  @override
  State<FaceAvatar> createState() => _FaceAvatarState();
}

class _FaceAvatarState extends State<FaceAvatar> {
  ui.Image? _img;
  Uint8List? _loadedFor;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant FaceAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.profile.face, _loadedFor)) _load();
  }

  void _load() {
    final bytes = widget.profile.face;
    _loadedFor = bytes;
    _img = FaceCache.peek(bytes);
    if (bytes == null) {
      _img = null;
      return;
    }
    FaceCache.get(bytes).then((img) {
      if (mounted && identical(_loadedFor, bytes)) setState(() => _img = img);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: CustomPaint(
        painter: _FacePainter(widget.profile.look, _img, widget.ring),
      ),
    );
  }
}

class _FacePainter extends CustomPainter {
  final CharacterLook look;
  final ui.Image? img;
  final bool ring;
  _FacePainter(this.look, this.img, this.ring);

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2 / (ring ? 1.1 : 1.0);
    CharacterPainter.paintFace(canvas, size.center(Offset.zero), r, look, face: img, ring: ring);
  }

  @override
  bool shouldRepaint(covariant _FacePainter old) =>
      old.img != img || old.look != look || old.look.toJson().toString() != look.toJson().toString();
}

/// Full-body animated character preview (used in customization and lobby).
class CharacterPreview extends StatefulWidget {
  final PlayerProfile profile;
  final double height;
  final bool animate;

  const CharacterPreview({super.key, required this.profile, this.height = 260, this.animate = true});

  @override
  State<CharacterPreview> createState() => _CharacterPreviewState();
}

class _CharacterPreviewState extends State<CharacterPreview> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<double> _time = ValueNotifier(0);
  ui.Image? _img;
  Uint8List? _loadedFor;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((d) => _time.value = d.inMicroseconds / 1e6);
    if (widget.animate) _ticker.start();
    _load();
  }

  void _load() {
    final bytes = widget.profile.face;
    _loadedFor = bytes;
    _img = FaceCache.peek(bytes);
    FaceCache.get(bytes).then((img) {
      if (mounted && identical(_loadedFor, bytes)) setState(() => _img = img);
    });
  }

  @override
  void didUpdateWidget(covariant CharacterPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.profile.face, _loadedFor)) _load();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: CustomPaint(
        size: Size.infinite,
        painter: _PreviewPainter(widget.profile, _img, _time),
      ),
    );
  }
}

class _PreviewPainter extends CustomPainter {
  final PlayerProfile profile;
  final ui.Image? img;
  final ValueNotifier<double> time;
  _PreviewPainter(this.profile, this.img, this.time) : super(repaint: time);

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    // fit the whole character (incl. the swinging paddle) inside the box
    final ppm = math.min(size.height / (2.45 * CharacterPainter.visualScale),
        size.width / (1.55 * CharacterPainter.visualScale));
    final feet = Offset(size.width / 2, size.height * 0.97);
    // swing every 2.4 s, cycling the three shots
    final cycle = t % 2.4;
    final swing = cycle < 0.32 ? 0.32 - cycle : 0.0;
    final kind = ShotKind.values[(t ~/ 2.4) % 3];
    CharacterPainter.paint(canvas, feet, ppm, profile.look,
        face: img,
        swing: swing,
        swingKind: kind,
        swingHand: 1,
        backView: false,
        time: t,
        runPhase: t * 0.6,
        moveSpeed: 0.6);
  }

  @override
  bool shouldRepaint(covariant _PreviewPainter old) => true;
}
