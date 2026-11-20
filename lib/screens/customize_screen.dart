import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../models/profile.dart';
import '../services/face_service.dart';
import '../ui/avatar.dart';
import '../ui/theme.dart';
import 'face_crop_screen.dart';

class CustomizeScreen extends StatefulWidget {
  final bool firstRun;
  const CustomizeScreen({super.key, this.firstRun = false});

  @override
  State<CustomizeScreen> createState() => _CustomizeScreenState();
}

class _CustomizeScreenState extends State<CustomizeScreen> with SingleTickerProviderStateMixin {
  late PlayerProfile _p;
  late final TextEditingController _name;
  late final TabController _tabs;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _p = AppScope.read(context).profile.copy();
    _name = TextEditingController(text: _p.name);
    _tabs = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _name.dispose();
    _tabs.dispose();
    super.dispose();
  }

  void _edit(void Function() f) => setState(f);

  Future<void> _pickFace(ImageSource src) async {
    setState(() => _busy = true);
    try {
      final pick = await FaceService.pick(src);
      if (pick == null || !mounted) return;
      final face = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(builder: (_) => FaceCropScreen(pick: pick)),
      );
      if (face != null && mounted) setState(() => _p.face = face);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not load photo: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editNumber() async {
    final result = await showDialog<int>(
      context: context,
      builder: (c) => _NumberPad(initial: _p.look.number, color: Color(_p.look.jersey)),
    );
    if (result != null) _edit(() => _p.look.number = result.clamp(0, 99));
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    _p.name = name.isEmpty ? 'Player' : (name.length > 14 ? name.substring(0, 14) : name);
    await AppScope.read(context).saveProfile(_p);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 290, child: _leftPanel()),
              Expanded(
                child: Column(
                  children: [
                    TabBar(
                      controller: _tabs,
                      indicatorColor: AppColors.lime,
                      labelColor: AppColors.lime,
                      unselectedLabelColor: AppColors.muted,
                      labelStyle: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.1, fontSize: 12),
                      dividerColor: Colors.transparent,
                      tabs: const [
                        Tab(icon: Icon(Icons.face_rounded, size: 20), text: 'FACE', height: 52),
                        Tab(icon: Icon(Icons.checkroom_rounded, size: 20), text: 'STYLE', height: 52),
                        Tab(icon: Icon(Icons.sports_tennis_rounded, size: 20), text: 'GEAR', height: 52),
                        Tab(icon: Icon(Icons.auto_awesome_rounded, size: 20), text: 'SPECIAL', height: 52),
                        Tab(icon: Icon(Icons.bolt_rounded, size: 20), text: 'STATS', height: 52),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabs,
                        children: [_faceTab(), _styleTab(), _gearTab(), _specialTab(), _statsTab()],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _leftPanel() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (!widget.firstRun)
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_rounded)),
              Expanded(
                child: Text(widget.firstRun ? 'CREATE YOUR PLAYER' : 'MY PLAYER',
                    style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.4)),
              ),
            ],
          ),
          Expanded(
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                Container(
                  height: 34,
                  margin: const EdgeInsets.symmetric(horizontal: 30, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: const RadialGradient(colors: [Color(0xFF3B87D3), Color(0x002B6CB5)]),
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: CharacterPreview(profile: _p, height: 999),
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: const Color(0x33D4F33A), borderRadius: BorderRadius.circular(10)),
                    child: Text('LV ${_p.level}', style: const TextStyle(color: AppColors.lime, fontWeight: FontWeight.w900)),
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _name,
                  maxLength: 14,
                  textCapitalization: TextCapitalization.words,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  decoration: const InputDecoration(
                      counterText: '', hintText: 'Your name', prefixIcon: Icon(Icons.person_rounded, size: 20)),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              PressScale(
                onTap: _editNumber,
                child: Container(
                  height: 50,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(color: const Color(0x22FFFFFF), borderRadius: BorderRadius.circular(14)),
                  child: Row(
                    children: [
                      Text('#${_p.look.number}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                      const SizedBox(width: 6),
                      const Icon(Icons.edit_rounded, size: 18, color: AppColors.lime),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          BigButton(
            label: widget.firstRun ? "LET'S PLAY" : 'SAVE',
            icon: Icons.check_circle_rounded,
            colors: const [AppColors.lime, Color(0xFF9CFF57)],
            onTap: _save,
          ),
        ],
      ),
    );
  }

  Widget _roundBtn(IconData icon, VoidCallback onTap) => PressScale(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(color: Color(0x22FFFFFF), shape: BoxShape.circle),
          child: Icon(icon, size: 18),
        ),
      );

  Widget _scroll(List<Widget> children) => ListView(
        padding: const EdgeInsets.fromLTRB(12, 10, 16, 12),
        children: children,
      );

  Widget _faceTab() {
    return _scroll([
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: GlassCard(
              child: Row(
                children: [
                  FaceAvatar(profile: _p, size: 80),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_p.face == null ? 'No photo yet' : 'Looking good!',
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                        const SizedBox(height: 4),
                        const Text(
                          'Your face appears on your character and on everyone\'s phone in multiplayer. '
                          'AI face detection crops it automatically.',
                          style: TextStyle(color: AppColors.muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 170,
            child: Column(
              children: [
                _actionTile(Icons.camera_alt_rounded, 'Take selfie', AppColors.lime,
                    _busy ? null : () => _pickFace(ImageSource.camera)),
                const SizedBox(height: 8),
                _actionTile(Icons.photo_library_rounded, 'From gallery', AppColors.blue,
                    _busy ? null : () => _pickFace(ImageSource.gallery)),
                if (_p.face != null) ...[
                  const SizedBox(height: 8),
                  _actionTile(Icons.delete_outline_rounded, 'Cartoon face', AppColors.pink,
                      () => setState(() => _p.face = null)),
                ],
              ],
            ),
          ),
        ],
      ),
      if (_busy) const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator())),
      const SizedBox(height: 12),
      const SectionLabel('Skin tone'),
      _swatches(AppColors.skins, _p.look.skin, (c) => _edit(() => _p.look.skin = c)),
      const SizedBox(height: 12),
      const SectionLabel('Hair (cartoon face)'),
      _swatches(AppColors.hairs, _p.look.hair, (c) => _edit(() => _p.look.hair = c)),
    ]);
  }

  Widget _actionTile(IconData icon, String label, Color color, VoidCallback? onTap) {
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: GlassCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        borderColor: color.withValues(alpha: 0.5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Flexible(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13))),
          ],
        ),
      ),
    );
  }

  Widget _swatches(List<int> colors, int selected, ValueChanged<int> onPick) {
    return Wrap(
      spacing: 9,
      runSpacing: 9,
      children: [
        for (final c in colors)
          PressScale(
            onTap: () => onPick(c),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Color(c),
                shape: BoxShape.circle,
                border: Border.all(color: c == selected ? AppColors.lime : Colors.white24, width: c == selected ? 3.5 : 1.5),
                boxShadow:
                    c == selected ? [BoxShadow(color: AppColors.lime.withValues(alpha: 0.5), blurRadius: 10)] : null,
              ),
              child: c == selected
                  ? Icon(Icons.check, size: 18, color: Color(c).computeLuminance() > 0.5 ? Colors.black : Colors.white)
                  : null,
            ),
          ),
      ],
    );
  }

  Widget _styleTab() {
    return _scroll([
      const SectionLabel('Jersey'),
      _swatches(AppColors.palette, _p.look.jersey, (c) => _edit(() => _p.look.jersey = c)),
      const SizedBox(height: 14),
      const SectionLabel('Shorts'),
      _swatches(AppColors.palette, _p.look.shorts, (c) => _edit(() => _p.look.shorts = c)),
      const SizedBox(height: 14),
      const SectionLabel('Shoes'),
      _swatches(AppColors.palette, _p.look.shoes, (c) => _edit(() => _p.look.shoes = c)),
    ]);
  }

  Widget _gearTab() {
    return _scroll([
      const SectionLabel('Paddle color'),
      _swatches(AppColors.palette, _p.look.paddle, (c) => _edit(() => _p.look.paddle = c)),
      const SizedBox(height: 14),
      const SectionLabel('Paddle design'),
      ChoiceChipRow<PaddlePattern>(
        values: PaddlePattern.values,
        selected: _p.look.pattern,
        label: (v) => v.label,
        onSelected: (v) => _edit(() => _p.look.pattern = v),
      ),
      const SizedBox(height: 14),
      const SectionLabel('Headwear & accessories'),
      ChoiceChipRow<Accessory>(
        values: Accessory.values,
        selected: _p.look.accessory,
        label: (v) => v.label,
        onSelected: (v) => _edit(() => _p.look.accessory = v),
      ),
    ]);
  }

  static const _specialIcons = {
    SpecialSkill.fireSmash: Icons.local_fire_department_rounded,
    SpecialSkill.iceFreeze: Icons.ac_unit_rounded,
    SpecialSkill.thunderCurve: Icons.bolt_rounded,
    SpecialSkill.phantomDrop: Icons.blur_on_rounded,
    SpecialSkill.tornadoLob: Icons.cyclone_rounded,
  };

  Widget _specialTab() {
    return _scroll([
      const Text(
        'Your special meter fills up when you hit the ball and win points. When it is full, tap SPECIAL: '
        'the game goes into slow motion and your next shot becomes your special attack.',
        style: TextStyle(color: AppColors.muted, fontSize: 12.5),
      ),
      const SizedBox(height: 10),
      for (final sk in SpecialSkill.values)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GlassCard(
            onTap: () => _edit(() => _p.special = sk),
            padding: const EdgeInsets.all(10),
            borderColor: _p.special == sk ? Color(sk.color) : null,
            gradient: _p.special == sk
                ? LinearGradient(colors: [Color(sk.color).withValues(alpha: 0.35), AppColors.card.withValues(alpha: 0.9)])
                : null,
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: Color(sk.color).withValues(alpha: 0.2), shape: BoxShape.circle),
                  child: Icon(_specialIcons[sk], color: Color(sk.color), size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(sk.label,
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Color(sk.color))),
                      Text(sk.description, style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
                if (_p.special == sk) const Icon(Icons.check_circle_rounded, color: AppColors.lime),
              ],
            ),
          ),
        ),
    ]);
  }

  Widget _statsTab() {
    final st = _p.stats;
    final left = PlayerStats.budget - st.total;
    Widget row(String name, String desc, IconData icon, Color color, int value, ValueChanged<int> set) {
      return GlassCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Text(name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                const SizedBox(width: 10),
                Expanded(child: Text(desc, style: const TextStyle(color: AppColors.muted, fontSize: 11.5))),
                _roundBtn(Icons.remove, () {
                  if (value > PlayerStats.minStat) _edit(() => set(value - 1));
                }),
                SizedBox(
                    width: 32,
                    child: Center(child: Text('$value', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)))),
                _roundBtn(Icons.add, () {
                  if (value < PlayerStats.maxStat && left > 0) _edit(() => set(value + 1));
                }),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                for (var i = 1; i <= PlayerStats.maxStat; i++)
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 7,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                          color: i <= value ? color : Colors.white12, borderRadius: BorderRadius.circular(4)),
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
    }

    return _scroll([
      Text(left > 0 ? '$left skill point${left == 1 ? '' : 's'} left to spend' : 'All skill points spent',
          style: TextStyle(fontWeight: FontWeight.w800, color: left > 0 ? AppColors.orange : AppColors.mint)),
      const SizedBox(height: 8),
      row('SPEED', 'Run speed ${st.runSpeed.toStringAsFixed(1)} m/s', Icons.directions_run_rounded, AppColors.blue,
          st.speed, (v) => st.speed = v),
      const SizedBox(height: 8),
      row('POWER', 'Faster POWER shots and smashes', Icons.flash_on_rounded, AppColors.orange, st.power,
          (v) => st.power = v),
      const SizedBox(height: 8),
      row('CONTROL', 'More accurate, fewer outs and net balls', Icons.gps_fixed_rounded, AppColors.mint, st.control,
          (v) => st.control = v),
    ]);
  }
}

/// Landscape-friendly number pad for the jersey number (no system keyboard).
class _NumberPad extends StatefulWidget {
  final int initial;
  final Color color;
  const _NumberPad({required this.initial, required this.color});

  @override
  State<_NumberPad> createState() => _NumberPadState();
}

class _NumberPadState extends State<_NumberPad> {
  late String _text = '${widget.initial}';
  bool _fresh = true; // first key press replaces the old number

  void _key(String k) {
    setState(() {
      if (k == '<') {
        _text = _text.length <= 1 ? '0' : _text.substring(0, _text.length - 1);
      } else if (_fresh || _text == '0') {
        _text = k;
      } else if (_text.length < 2) {
        _text += k;
      }
      _fresh = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget key(String k) => Padding(
          padding: const EdgeInsets.all(4),
          child: PressScale(
            onTap: () => _key(k),
            child: Container(
              width: 62,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: const Color(0x22FFFFFF), borderRadius: BorderRadius.circular(14)),
              child: k == '<'
                  ? const Icon(Icons.backspace_rounded, size: 22)
                  : Text(k, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            ),
          ),
        );
    return Dialog(
      backgroundColor: AppColors.card,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // big preview of the number on a jersey-colored badge
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('JERSEY NUMBER',
                    style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w900, letterSpacing: 1.4, fontSize: 12)),
                const SizedBox(height: 8),
                Container(
                  width: 120,
                  height: 120,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: widget.color,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                  child: Text(_text,
                      style: TextStyle(
                          fontSize: 54,
                          fontWeight: FontWeight.w900,
                          color: widget.color.computeLuminance() > 0.55 ? const Color(0xFF111111) : Colors.white)),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
                    const SizedBox(width: 6),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, int.tryParse(_text) ?? 0),
                      style: FilledButton.styleFrom(backgroundColor: AppColors.lime, foregroundColor: AppColors.bg),
                      child: const Text('OK', style: TextStyle(fontWeight: FontWeight.w900)),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(width: 16),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final row in const [
                  ['1', '2', '3'],
                  ['4', '5', '6'],
                  ['7', '8', '9'],
                  ['', '0', '<'],
                ])
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [for (final k in row) k.isEmpty ? const SizedBox(width: 70, height: 56) : key(k)],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
