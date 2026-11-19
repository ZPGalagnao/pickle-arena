import 'package:material_ui/material_ui.dart';

import '../services/sound_service.dart';

class AppColors {
  static const bg = Color(0xFF07101F);
  static const bg2 = Color(0xFF0E2140);
  static const card = Color(0xFF13284A);
  static const cardHi = Color(0xFF1B3762);
  static const lime = Color(0xFFD4F33A);
  static const blue = Color(0xFF2D9CDB);
  static const orange = Color(0xFFFF7A3D);
  static const pink = Color(0xFFFF4D8D);
  static const purple = Color(0xFF9B6BFF);
  static const mint = Color(0xFF00E5A0);
  static const text = Color(0xFFF2F6FF);
  static const muted = Color(0xFF8EA3C7);

  static const palette = <int>[
    0xFF2D9CDB, 0xFF1565C0, 0xFF00BFA5, 0xFF2E7D32, 0xFFD4F33A, 0xFFFFC400,
    0xFFFF7A3D, 0xFFE53935, 0xFFFF4D8D, 0xFF9B6BFF, 0xFF6A1B9A, 0xFF37474F,
    0xFF111111, 0xFFFFFFFF, 0xFF8D6E63, 0xFF90A4AE,
  ];
  static const skins = <int>[
    0xFFFFE0BD, 0xFFF1C27D, 0xFFE0AC69, 0xFFC68642, 0xFF8D5524, 0xFF5C3A1E,
  ];
  static const hairs = <int>[
    0xFF1B1B1B, 0xFF4E342E, 0xFF8D6E63, 0xFFE6C27A, 0xFFB71C1C, 0xFF90A4AE, 0xFF7E57C2,
  ];
}

ThemeData buildTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.lime,
      brightness: Brightness.dark,
      primary: AppColors.lime,
      secondary: AppColors.blue,
      surface: AppColors.card,
    ),
    scaffoldBackgroundColor: AppColors.bg,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: AppColors.text, displayColor: AppColors.text),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(fontFamily: 'Roboto', fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1.5),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: AppColors.lime,
      thumbColor: AppColors.lime,
      inactiveTrackColor: Color(0x33FFFFFF),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.bg : Colors.white70),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.lime : Colors.white24),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0x22FFFFFF),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

/// Dark navy gradient used behind every screen.
class AppBackground extends StatelessWidget {
  final Widget child;
  const AppBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0B1A33), AppColors.bg, Color(0xFF050B16)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -120,
            right: -80,
            child: _Glow(color: AppColors.blue.withValues(alpha: 0.25), size: 320),
          ),
          Positioned(
            bottom: -140,
            left: -100,
            child: _Glow(color: AppColors.lime.withValues(alpha: 0.12), size: 360),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  final Color color;
  final double size;
  const _Glow({required this.color, required this.size});

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
          ),
        ),
      );
}

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final VoidCallback? onTap;
  final Gradient? gradient;
  final Color? borderColor;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.onTap,
    this.gradient,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? AppColors.card.withValues(alpha: 0.85)) : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderColor ?? Colors.white.withValues(alpha: 0.08), width: 1.2),
        boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 18, offset: Offset(0, 8))],
      ),
      child: child,
    );
    if (onTap == null) return box;
    return PressScale(onTap: onTap!, child: box);
  }
}

/// Shrinks a little while pressed - makes buttons feel physical.
class PressScale extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const PressScale({super.key, required this.child, required this.onTap});

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: () {
        Sound.I.play('ui_click', volume: 0.5);
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _down ? 0.95 : 1,
        duration: const Duration(milliseconds: 90),
        child: widget.child,
      ),
    );
  }
}

class BigButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback? onTap;
  final Color textColor;
  final String? subtitle;

  const BigButton({
    super.key,
    required this.label,
    required this.icon,
    required this.colors,
    this.onTap,
    this.textColor = AppColors.bg,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: PressScale(
        onTap: onTap ?? () {},
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: colors),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(color: colors.first.withValues(alpha: 0.4), blurRadius: 18, offset: const Offset(0, 6)),
            ],
          ),
          child: LayoutBuilder(builder: (context, box) {
            // narrow buttons (e.g. two side by side) drop the chevron and shrink the label
            final compact = box.maxWidth < 200;
            final title = Text(label,
                maxLines: 1,
                style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1.2));
            if (compact) {
              return FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [Icon(icon, color: textColor, size: 24), const SizedBox(width: 8), title],
                ),
              );
            }
            return Row(
              children: [
                Icon(icon, color: textColor, size: 28),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      title,
                      if (subtitle != null)
                        Text(subtitle!,
                            style: TextStyle(
                                color: textColor.withValues(alpha: 0.75),
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: textColor),
              ],
            );
          }),
        ),
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.6)),
      );
}

class ChoiceChipRow<T> extends StatelessWidget {
  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onSelected;

  const ChoiceChipRow({
    super.key,
    required this.values,
    required this.selected,
    required this.label,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final v in values)
          PressScale(
            onTap: () => onSelected(v),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: v == selected ? AppColors.lime : const Color(0x22FFFFFF),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Text(label(v),
                  style: TextStyle(
                      color: v == selected ? AppColors.bg : AppColors.text,
                      fontWeight: FontWeight.w800)),
            ),
          ),
      ],
    );
  }
}

class GameLogo extends StatelessWidget {
  final double size;
  const GameLogo({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ShaderMask(
          shaderCallback: (r) => const LinearGradient(
            colors: [AppColors.lime, Color(0xFF9CFF57), AppColors.mint],
          ).createShader(r),
          child: Text('PICKLE',
              style: TextStyle(
                  fontSize: size,
                  fontWeight: FontWeight.w900,
                  fontStyle: FontStyle.italic,
                  letterSpacing: 4,
                  height: 1,
                  color: Colors.white)),
        ),
        Text('ARENA',
            style: TextStyle(
                fontSize: size * 0.55,
                fontWeight: FontWeight.w900,
                fontStyle: FontStyle.italic,
                letterSpacing: size * 0.35,
                height: 1.1,
                color: Colors.white)),
      ],
    );
  }
}
