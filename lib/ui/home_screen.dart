import 'package:flutter/material.dart';

import '../audio/mixer.dart';
import '../models/mix_store.dart';
import '../models/sounds.dart';
import 'theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.mixer, required this.store});

  final Mixer mixer;
  final MixStore store;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Mix> _saved = [];

  Mixer get mixer => widget.mixer;

  @override
  void initState() {
    super.initState();
    widget.store.load().then((m) {
      if (mounted) setState(() => _saved = m);
    });
  }

  Future<void> _saveMix() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Night.dusk,
        title: const Text('Save this mix'),
        content: TextField(
          key: const Key('mix-name'),
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Name, e.g. Sunday rain'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Save')),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    final mixes = [..._saved.where((m) => m.name != name.trim()), mixer.currentMix(name.trim())];
    await widget.store.save(mixes);
    setState(() => _saved = mixes);
  }

  Future<void> _deleteMix(Mix mix) async {
    final mixes = _saved.where((m) => m.name != mix.name).toList();
    await widget.store.save(mixes);
    setState(() => _saved = mixes);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: mixer,
      builder: (context, _) => Scaffold(
        // the controls stay at the bottom, within thumb reach, while the
        // sound grid scrolls above them
        bottomNavigationBar: SafeArea(child: _NowPlaying(mixer: mixer, onSave: _saveMix)),
        body: SafeArea(
          child: CustomScrollView(
            slivers: [
              const SliverToBoxAdapter(child: _Header()),
              SliverToBoxAdapter(
                child: _MixRow(
                  presets: presets,
                  saved: _saved,
                  onPick: mixer.applyMix,
                  onDelete: _deleteMix,
                ),
              ),
              for (final group in SoundGroup.values) ...[
                SliverToBoxAdapter(child: _SectionTitle(group == SoundGroup.nature ? 'Nature' : 'Noise & rhythm')),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverGrid.count(
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.55,
                    children: [
                      for (final s in sounds.where((s) => s.group == group)) _SoundTile(sound: s, mixer: mixer),
                    ],
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                center: Alignment(-0.3, -0.3),
                colors: [Color(0xFFFFF6D8), Night.moon, Color(0xFFC9AE6C)],
              ),
              boxShadow: [BoxShadow(color: Night.moon.withValues(alpha: 0.18), blurRadius: 30, spreadRadius: 6)],
            ),
          ),
          const SizedBox(width: 14),
          Text('Moonhush',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w300,
                    fontFamily: 'serif',
                  )),
        ],
      ),
    );
  }
}

class _NowPlaying extends StatelessWidget {
  const _NowPlaying({required this.mixer, required this.onSave});

  final Mixer mixer;
  final VoidCallback onSave;

  static const _timers = <String, Duration?>{
    'Off': null,
    '15 min': Duration(minutes: 15),
    '30 min': Duration(minutes: 30),
    '1 h': Duration(hours: 1),
    '8 h': Duration(hours: 8),
  };

  String _status() {
    if (!mixer.hasSound) return 'Tap a sound to start';
    final names = [for (final id in mixer.activeIds) soundById(id).name].join(', ');
    final left = mixer.sleepRemaining;
    if (left == null) return names;
    final mins = (left.inSeconds / 60).ceil();
    return '$names · stops in $mins min';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Night.dusk,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Night.line),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton.filled(
                key: const Key('play-pause'),
                onPressed: !mixer.hasSound ? null : (mixer.isPlaying ? mixer.pause : mixer.resume),
                icon: Icon(mixer.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(_status(),
                    key: const Key('status'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Night.mist)),
              ),
              IconButton(
                tooltip: 'Save mix',
                onPressed: mixer.hasSound ? onSave : null,
                icon: const Icon(Icons.bookmark_add_outlined),
              ),
              IconButton(
                tooltip: 'Stop all',
                onPressed: mixer.hasSound ? () => mixer.stopAll() : null,
                icon: const Icon(Icons.stop_rounded),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Text('SLEEP TIMER', style: TextStyle(fontSize: 11, letterSpacing: 1.2, color: Night.mist)),
              ),
              for (final e in _timers.entries)
                ChoiceChip(
                  label: Text(e.key),
                  selected: mixer.sleepAfter == e.value,
                  onSelected: (_) => mixer.setSleepTimer(e.value),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MixRow extends StatelessWidget {
  const _MixRow({required this.presets, required this.saved, required this.onPick, required this.onDelete});

  final List<Mix> presets;
  final List<Mix> saved;
  final ValueChanged<Mix> onPick;
  final ValueChanged<Mix> onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Mixes'),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final m in saved)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InputChip(
                    avatar: const Icon(Icons.bookmark, size: 16, color: Night.moon),
                    label: Text(m.name),
                    onPressed: () => onPick(m),
                    onDeleted: () => onDelete(m),
                  ),
                ),
              for (final m in presets)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(label: Text(m.name), onPressed: () => onPick(m)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      child: Text(text,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w300, fontFamily: 'serif')),
    );
  }
}

class _SoundTile extends StatelessWidget {
  const _SoundTile({required this.sound, required this.mixer});

  final Sound sound;
  final Mixer mixer;

  @override
  Widget build(BuildContext context) {
    final on = mixer.isOn(sound.id);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: on ? const Color(0xFF252A52) : Night.tile,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: on ? Night.moon : Night.line),
        boxShadow: on ? [BoxShadow(color: Night.moon.withValues(alpha: 0.12), blurRadius: 18)] : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: Key('tile-${sound.id}'),
          borderRadius: BorderRadius.circular(14),
          onTap: () => mixer.toggle(sound.id),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(sound.name,
                          style: const TextStyle(fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: on ? Night.moon : Night.line,
                        ),
                      ),
                    ),
                  ],
                ),
                Opacity(
                  opacity: on ? 1 : 0.35,
                  child: Slider(
                    value: mixer.volumeOf(sound.id),
                    onChanged: (v) => mixer.setVolume(sound.id, v),
                    semanticFormatterCallback: (v) => '${sound.name} volume ${(v * 100).round()}%',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
