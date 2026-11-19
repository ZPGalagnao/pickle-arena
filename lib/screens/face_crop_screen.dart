import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../services/face_service.dart';
import '../ui/theme.dart';

/// Lets the player drag / pinch the circle over their face.
/// Returns the final 256x256 face JPEG.
class FaceCropScreen extends StatefulWidget {
  final FacePick pick;
  const FaceCropScreen({super.key, required this.pick});

  @override
  State<FaceCropScreen> createState() => _FaceCropScreenState();
}

class _FaceCropScreenState extends State<FaceCropScreen> {
  ui.Image? _image;
  late Rect _crop;
  Rect _startCrop = Rect.zero;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _crop = widget.pick.crop;
    ui.instantiateImageCodec(widget.pick.bytes).then((c) => c.getNextFrame()).then((f) {
      if (mounted) setState(() => _image = f.image);
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final Uint8List face = await FaceService.cropToFace(widget.pick.bytes, _crop);
    if (mounted) Navigator.of(context).pop(face);
  }

  @override
  Widget build(BuildContext context) {
    final found = widget.pick.facesFound;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('ADJUST YOUR FACE')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Icon(found > 0 ? Icons.face_retouching_natural : Icons.help_outline,
                      color: found > 0 ? AppColors.lime : AppColors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      found > 0
                          ? 'AI found ${found == 1 ? 'your face' : '$found faces (using the biggest)'}. Drag or pinch to fine-tune.'
                          : 'No face detected. Drag the circle over your face and pinch to resize.',
                      style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _image == null
                  ? const Center(child: CircularProgressIndicator())
                  : LayoutBuilder(builder: (context, box) {
                      final iw = widget.pick.width.toDouble(), ih = widget.pick.height.toDouble();
                      final scale = math.min(box.maxWidth / iw, box.maxHeight / ih);
                      final dx = (box.maxWidth - iw * scale) / 2, dy = (box.maxHeight - ih * scale) / 2;
                      return GestureDetector(
                        onScaleStart: (_) => _startCrop = _crop,
                        onScaleUpdate: (d) {
                          final size = _startCrop.width / d.scale;
                          final c = _crop.center + d.focalPointDelta / scale;
                          setState(() {
                            _crop = FaceService.clampCrop(c.dx, c.dy,
                                d.pointerCount > 1 ? size : _crop.width, widget.pick.width, widget.pick.height);
                          });
                        },
                        child: CustomPaint(
                          size: Size(box.maxWidth, box.maxHeight),
                          painter: _CropPainter(_image!, _crop, scale, Offset(dx, dy)),
                        ),
                      );
                    }),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                      child: const Text('CANCEL', style: TextStyle(fontWeight: FontWeight.w900)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _saving || _image == null ? null : _save,
                      icon: _saving
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.check_rounded),
                      label: const Text('USE THIS FACE', style: TextStyle(fontWeight: FontWeight.w900)),
                      style: FilledButton.styleFrom(
                          backgroundColor: AppColors.lime,
                          foregroundColor: AppColors.bg,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CropPainter extends CustomPainter {
  final ui.Image image;
  final Rect crop;
  final double scale;
  final Offset offset;
  _CropPainter(this.image, this.crop, this.scale, this.offset);

  @override
  void paint(Canvas canvas, Size size) {
    final dst = Rect.fromLTWH(offset.dx, offset.dy, image.width * scale, image.height * scale);
    canvas.drawImageRect(image, Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()), dst,
        Paint()..filterQuality = FilterQuality.medium);
    final c = offset + crop.center * scale;
    final r = crop.width / 2 * scale;
    final shade = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addOval(Rect.fromCircle(center: c, radius: r));
    canvas.drawPath(shade, Paint()..color = const Color(0xAA000000));
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = AppColors.lime);
  }

  @override
  bool shouldRepaint(covariant _CropPainter old) => old.crop != crop || old.image != image;
}
