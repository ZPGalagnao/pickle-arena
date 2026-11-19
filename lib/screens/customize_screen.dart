import 'package:material_ui/material_ui.dart';
import 'package:image_picker/image_picker.dart';

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
    _tabs = TabController(length: 4, vsync: this);
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
      final face = await Navigator.of(context).push<dynamic>(
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

  Future<void> _save() async {
    final name = _name.text.trim();
    _p.name = name.isEmpty ? 'Player' : (name.length > 14 ? name.substring(0, 14) : name);
    await AppScope.read(context).saveProfile(_p);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.firstRun ? 'CREATE YOUR PLAYER' : 'MY PLAYER'),
        automaticallyImplyLeading: !widget.firstRun,
      ),
      extendBodyBehindAppBar: false,
      body: AppBackground(
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              _header(),
              TabBar(
                controller: _tabs,
                indicatorColor: AppColors.lime,
                labelColor: AppColors.lime,
                unselectedLabelColor: AppColors.muted,
                labelStyle: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2),
                dividerColor: Colors.transparent,
                tabs: const [
                  Tab(icon: Icon(Icons.face_rounded), text: 'FACE'),
                  Tab(icon: Icon(Icons.checkroom_rounded), text: 'STYLE'),
                  Tab(icon: Icon(Icons.sports_tennis_rounded), text: 'GEAR'),
                  Tab(icon: Icon(Icons.bolt_rounded), text: 'STATS'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [_faceTab(), _styleTab(), _gearTab(), _statsTab()],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: BigButton(
                  label: widget.firstRun ? "LET'S PLAY" : 'SAVE PLAYER',
                  icon: Icons.check_circle_rounded,
                  colors: const [AppColors.lime, Color(0xFF9CFF57)],
                  onTap: _save,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return SizedBox(
      height: 230,
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                Container(
                  height: 40,
                  margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: const RadialGradient(colors: [Color(0xFF3B87D3), Color(0x002B6CB5)]),
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: CharacterPreview(profile: _p, height: 210),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 6,
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionLabel('Player name'),
                  TextField(
                    controller: _name,
                    maxLength: 14,
                    textCapitalization: TextCapitalization.words,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                    decoration: const InputDecoration(counterText: '', hintText: 'Your name'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  const SectionLabel('Jersey number'),
                  Row(
                    children: [
                      _roundBtn(Icons.remove, () => _edit(() => _p.look.number = (_p.look.number - 1).clamp(0, 99))),
                      Expanded(
                        child: Center(
                          child: Text('${_p.look.number}',
                              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
                        ),
                      ),
                      _roundBtn(Icons.add, () => _edit(() => _p.look.number = (_p.look.number + 1).clamp(0, 99))),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _roundBtn(IconData icon, VoidCallback onTap) => PressScale(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(color: Color(0x22FFFFFF), shape: BoxShape.circle),
          child: Icon(icon, size: 20),
        ),
      );

  Widget _scroll(List<Widget> children) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        children: children,
      );

  Widget _faceTab() {
    return _scroll([
      GlassCard(
        child: Row(
          children: [
            FaceAvatar(profile: _p, size: 92),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_p.face == null ? 'No photo yet' : 'Looking good!',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                  const SizedBox(height: 4),
                  const Text(
                    'Your face appears on your character and on your opponent\'s phone. '
                    'AI face detection crops it automatically.',
                    style: TextStyle(color: AppColors.muted, fontSize: 12.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: _actionTile(Icons.camera_alt_rounded, 'Take selfie', AppColors.lime,
                _busy ? null : () => _pickFace(ImageSource.camera)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _actionTile(Icons.photo_library_rounded, 'From gallery', AppColors.blue,
                _busy ? null : () => _pickFace(ImageSource.gallery)),
          ),
        ],
      ),
      if (_p.face != null) ...[
        const SizedBox(height: 10),
        _actionTile(Icons.delete_outline_rounded, 'Use cartoon face instead', AppColors.pink,
            () => setState(() => _p.face = null)),
      ],
      if (_busy) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
      const SizedBox(height: 16),
      const SectionLabel('Skin tone'),
      _swatches(AppColors.skins, _p.look.skin, (c) => _edit(() => _p.look.skin = c)),
      const SizedBox(height: 16),
      const SectionLabel('Hair (cartoon face)'),
      _swatches(AppColors.hairs, _p.look.hair, (c) => _edit(() => _p.look.hair = c)),
    ]);
  }

  Widget _actionTile(IconData icon, String label, Color color, VoidCallback? onTap) {
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: GlassCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        borderColor: color.withValues(alpha: 0.5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 8),
            Flexible(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800))),
          ],
        ),
      ),
    );
  }

  Widget _swatches(List<int> colors, int selected, ValueChanged<int> onPick) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final c in colors)
          PressScale(
            onTap: () => onPick(c),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Color(c),
                shape: BoxShape.circle,
                border: Border.all(
                    color: c == selected ? AppColors.lime : Colors.white24, width: c == selected ? 3.5 : 1.5),
                boxShadow: c == selected
                    ? [BoxShadow(color: AppColors.lime.withValues(alpha: 0.5), blurRadius: 10)]
                    : null,
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
      const SizedBox(height: 18),
      const SectionLabel('Shorts'),
      _swatches(AppColors.palette, _p.look.shorts, (c) => _edit(() => _p.look.shorts = c)),
      const SizedBox(height: 18),
      const SectionLabel('Shoes'),
      _swatches(AppColors.palette, _p.look.shoes, (c) => _edit(() => _p.look.shoes = c)),
    ]);
  }

  Widget _gearTab() {
    return _scroll([
      const SectionLabel('Paddle color'),
      _swatches(AppColors.palette, _p.look.paddle, (c) => _edit(() => _p.look.paddle = c)),
      const SizedBox(height: 18),
      const SectionLabel('Paddle design'),
      ChoiceChipRow<PaddlePattern>(
        values: PaddlePattern.values,
        selected: _p.look.pattern,
        label: (v) => v.label,
        onSelected: (v) => _edit(() => _p.look.pattern = v),
      ),
      const SizedBox(height: 18),
      const SectionLabel('Headwear & accessories'),
      ChoiceChipRow<Accessory>(
        values: Accessory.values,
        selected: _p.look.accessory,
        label: (v) => v.label,
        onSelected: (v) => _edit(() => _p.look.accessory = v),
      ),
    ]);
  }

  Widget _statsTab() {
    final st = _p.stats;
    final left = PlayerStats.budget - st.total;
    Widget row(String name, String desc, IconData icon, Color color, int value, ValueChanged<int> set) {
      return GlassCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Text(name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                const Spacer(),
                _roundBtn(Icons.remove, () {
                  if (value > PlayerStats.minStat) _edit(() => set(value - 1));
                }),
                SizedBox(
                    width: 36,
                    child: Center(
                        child: Text('$value', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)))),
                _roundBtn(Icons.add, () {
                  if (value < PlayerStats.maxStat && left > 0) _edit(() => set(value + 1));
                }),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (var i = 1; i <= PlayerStats.maxStat; i++)
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: i <= value ? color : Colors.white12,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(desc, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          ],
        ),
      );
    }

    return _scroll([
      GlassCard(
        gradient: LinearGradient(colors: [
          (left > 0 ? AppColors.orange : AppColors.mint).withValues(alpha: 0.35),
          AppColors.card.withValues(alpha: 0.6)
        ]),
        child: Row(
          children: [
            const Icon(Icons.stars_rounded, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Text(left > 0 ? '$left skill point${left == 1 ? '' : 's'} left to spend' : 'All skill points spent',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      row('SPEED', 'How fast you run (${st.runSpeed.toStringAsFixed(1)} m/s)', Icons.directions_run_rounded,
          AppColors.blue, st.speed, (v) => st.speed = v),
      const SizedBox(height: 10),
      row('POWER', 'Faster drives and smashes', Icons.flash_on_rounded, AppColors.orange, st.power,
          (v) => st.power = v),
      const SizedBox(height: 10),
      row('CONTROL', 'More accurate shots, fewer outs and net balls', Icons.gps_fixed_rounded, AppColors.mint,
          st.control, (v) => st.control = v),
    ]);
  }
}
