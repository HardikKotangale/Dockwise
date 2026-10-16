import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/key_capture.dart';
import '../../../core/palette.dart';
import '../../../domain/standby_models.dart';
import '../../../services/city_search.dart';
import '../../../state/standby_controller.dart';
import '../widgets/clock_faces.dart';
import '../widgets/mini_keyboard.dart';

/// Row showing the chosen second city; opens the city search page.
class CityRow extends StatelessWidget {
  const CityRow({
    super.key,
    required this.settings,
    required this.onTap,
    this.onChanged,
  });

  final StandbySettings settings;
  final VoidCallback onTap;

  /// With this, a city that is set gets a trash button that clears it.
  final ValueChanged<StandbySettings>? onChanged;

  @override
  Widget build(BuildContext context) {
    final name = settings.worldCity.isNotEmpty
        ? settings.worldCity
        : (settings.worldZone.isEmpty
              ? 'Not set'
              : zoneLabel(settings.worldZone));
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text(
        'Second city',
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(name),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onChanged != null && settings.worldZone.isNotEmpty)
            IconButton(
              tooltip: 'Remove the second city',
              icon: const Icon(
                Icons.delete_outline_rounded,
                color: Color(0xFFFF453A),
              ),
              onPressed: () => onChanged!(
                settings.copyWith(
                  worldZone: '',
                  worldCity: '',
                  worldLat: 0,
                  worldLon: 0,
                ),
              ),
            ),
          const Icon(Icons.chevron_right_rounded, color: Colors.white38),
        ],
      ),
      onTap: onTap,
    );
  }
}

/// Search any city in the world. The field stays pinned at the top so the
/// keyboard never hides what you type.
class CityPage extends StatefulWidget {
  const CityPage({super.key, required this.controller, required this.onDone});

  final StandbyController controller;
  final VoidCallback onDone;

  @override
  State<CityPage> createState() => _CityPageState();
}

class _CityPageState extends State<CityPage> {
  final _text = TextEditingController();
  Timer? _debounce;
  List<CityResult> _results = const [];
  bool _loading = false;
  bool _offline = false;
  bool _keyboard = !onComputer;

  @override
  void dispose() {
    _debounce?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _changed(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) {
      setState(() => _results = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(q));
  }

  Future<void> _search(String q) async {
    setState(() => _loading = true);
    List<CityResult> found;
    var offline = false;
    try {
      found = await searchCities(q);
    } catch (_) {
      // no internet: fall back to the built-in list of major cities
      offline = true;
      found = [
        for (final id in searchZones(q))
          CityResult(
            name: zoneLabel(id),
            region: id.split('/').first,
            timezone: id,
          ),
      ];
    }
    if (!mounted || _text.text != q) return;
    setState(() {
      _results = found;
      _offline = offline;
      _loading = false;
    });
  }

  void _type(String ch) {
    _text.text += ch;
    _changed(_text.text);
  }

  void _backspace() {
    if (_text.text.isEmpty) return;
    _text.text = _text.text.substring(0, _text.text.length - 1);
    _changed(_text.text);
  }

  void _pick(CityResult r) {
    final c = widget.controller;
    c.updateSettings(
      c.settings.copyWith(
        worldZone: r.timezone,
        worldCity: r.name,
        worldLat: r.latitude ?? 0,
        worldLon: r.longitude ?? 0,
      ),
    );
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Column(
        children: [
          // readOnly: typing uses our own keyboard, never the system one
          TextField(
            controller: _text,
            // a phone types on our own keyboard, never the system one; a
            // computer types straight into the field
            readOnly: !onComputer,
            autofocus: onComputer,
            showCursor: true,
            enableInteractiveSelection: onComputer,
            textInputAction: TextInputAction.search,
            style: const TextStyle(fontSize: 17),
            onChanged: onComputer
                ? (q) {
                    setState(() {});
                    _changed(q);
                  }
                : null,
            onSubmitted: onComputer
                ? (_) {
                    if (_results.isNotEmpty) _pick(_results.first);
                  }
                : null,
            onTap: onComputer ? null : () => setState(() => _keyboard = true),
            decoration: InputDecoration(
              hintText: onComputer
                  ? 'Type a city, then Enter'
                  : 'Search any city in the world',
              hintStyle: const TextStyle(color: Colors.white60),
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: Colors.white54,
              ),
              suffixIcon: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : (_text.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear',
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _text.clear();
                              _changed('');
                            },
                          )),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          if (_offline)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Offline: showing major cities only',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 10),
              children: [
                // results as one rounded group with hairlines, like iOS lists
                if (_results.isNotEmpty)
                  Material(
                    color: Colors.white.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(14),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (var i = 0; i < _results.length; i++) ...[
                          if (i > 0)
                            const Divider(height: 1, indent: 16, endIndent: 0),
                          ListTile(
                            title: Text(_results[i].name),
                            subtitle: Text(_results[i].region),
                            onTap: () => _pick(_results[i]),
                          ),
                        ],
                      ],
                    ),
                  ),
                if (c.settings.worldZone.isNotEmpty)
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: Palette.red),
                    onPressed: () {
                      c.updateSettings(
                        c.settings.copyWith(
                          worldZone: '',
                          worldCity: '',
                          worldLat: 0,
                          worldLon: 0,
                        ),
                      );
                      widget.onDone();
                    },
                    child: const Text('Remove second city'),
                  ),
              ],
            ),
          ),
          if (_keyboard)
            MiniKeyboard(
              onChar: _type,
              onBackspace: _backspace,
              onDone: () => setState(() => _keyboard = false),
            ),
        ],
      ),
    );
  }
}
