import 'dart:async';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;

import 'package:flutter/material.dart';
import '../../../services/spotify_service.dart';
import '../../../state/standby_controller.dart';

/// Music settings shown in the dock: Spotify login, where to play, playlists,
/// and phone (notification-access) control.
class MusicSourcesPanel extends StatefulWidget {
  const MusicSourcesPanel({
    super.key,
    required this.controller,
    this.onAllSettings,
  });

  final StandbyController controller;
  final VoidCallback? onAllSettings;

  @override
  State<MusicSourcesPanel> createState() => _MusicSourcesPanelState();
}

class _MusicSourcesPanelState extends State<MusicSourcesPanel> {
  // Cached so the lists are not re-fetched on every music refresh.
  List<SpotifyDevice>? _devices; // kept on screen while it reloads
  Future<List<SpotifyPlaylist>>? _playlists;
  late Future<List<({String package, String app})>> _players;

  StandbyController get c => widget.controller;

  Timer? _poll;

  // the device you just chose: shown as playing until Spotify confirms it
  String? _pendingActive;
  DateTime _pendingUntil = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> _loadDevices() async {
    final list = await c.spotifyDevices();
    if (!mounted) return;
    if (_pendingActive != null) {
      final active = list.where((d) => d.isActive).firstOrNull?.id;
      if (active == _pendingActive || DateTime.now().isAfter(_pendingUntil)) {
        _pendingActive = null; // confirmed, or Spotify never switched: trust it
      } else {
        return; // Spotify is still switching: keep showing your choice
      }
    }
    setState(() => _devices = list);
  }

  void _load() {
    _loadDevices();
    _playlists ??= c.spotifyPlaylists();
  }

  @override
  void initState() {
    super.initState();
    _players = c.mediaPlayers();
    if (c.spotifyConnected) {
      _load();
      // follow changes made elsewhere (another device, the Spotify app itself)
      _poll = Timer.periodic(const Duration(seconds: 5), (_) => _loadDevices());
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _connect() async {
    final ok = await c.connectSpotify();
    if (!mounted) return;
    if (ok) {
      setState(_load);
    } else {
      _toast('Could not connect to Spotify');
    }
  }

  Future<void> _run(
    Future<bool> Function() action, {
    String? makeActive,
  }) async {
    if (makeActive != null) {
      _pendingActive = makeActive;
      _pendingUntil = DateTime.now().add(const Duration(seconds: 4));
    }
    if (makeActive != null && _devices != null) {
      // show your choice at once; Spotify needs a second or two to switch, and
      // asking it again straight away would still say the old device plays
      setState(() {
        _devices = [
          for (final d in _devices!)
            SpotifyDevice(
              d.id,
              d.name,
              d.type,
              d.id == makeActive,
              volume: d.volume,
            ),
        ];
      });
    }
    final ok = await action();
    if (!ok && mounted) _toast(c.musicError ?? 'Could not play');
    if (!mounted) return;
    if (!ok) {
      _pendingActive = null;
      unawaited(_loadDevices()); // put the list back to what is really playing
      return;
    }
    // confirm with Spotify once it has switched (twice, in case it is slow)
    for (final ms in const [900, 2200]) {
      unawaited(
        Future.delayed(Duration(milliseconds: ms), () {
          if (mounted) _loadDevices();
        }),
      );
    }
  }

  IconData _icon(String type) => switch (type) {
    'Computer' => Icons.laptop_mac,
    'Smartphone' => Icons.smartphone,
    'Tablet' => Icons.tablet_android,
    'TV' => Icons.tv,
    _ => Icons.speaker,
  };

  @override
  Widget build(BuildContext context) {
    const heading = TextStyle(fontWeight: FontWeight.w900, fontSize: 17);
    final source = c.settings.musicSource;
    void pick(String value) =>
        c.updateSettings(c.settings.copyWith(musicSource: value));
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        if (c.spotifyConnected) ...[
          SpotifyVolume(controller: c),
          const SizedBox(height: 20),
        ],
        // Which player the card follows (and controls).
        Row(
          children: [
            const Expanded(child: Text('Show music from', style: heading)),
            IconButton(
              tooltip: 'Refresh players',
              onPressed: () => setState(() => _players = c.mediaPlayers()),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        FutureBuilder<List<({String package, String app})>>(
          future: _players,
          builder: (context, snap) => Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Auto'),
                selected: source == 'auto',
                onSelected: (_) => pick('auto'),
              ),
              if (c.spotifyConnected)
                ChoiceChip(
                  label: const Text('Spotify account'),
                  selected: source == 'spotify',
                  onSelected: (_) => pick('spotify'),
                ),
              for (final p
                  in snap.data ?? const <({String package, String app})>[])
                ChoiceChip(
                  label: Text(p.app),
                  selected: source == p.package,
                  onSelected: (_) => pick(p.package),
                ),
            ],
          ),
        ),
        const Divider(height: 32),
        Row(
          children: [
            const Expanded(child: Text('Spotify', style: heading)),
            if (c.spotifyConnected)
              TextButton.icon(
                onPressed: () async {
                  await c.disconnectSpotify();
                  if (mounted) {
                    setState(() {
                      _playlists = null;
                      _devices = null;
                    });
                  }
                },
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('Sign out'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (!c.spotifyConfigured)
          const Text('Build with --dart-define=SPOTIFY_CLIENT_ID=YOUR_ID.')
        else if (!c.spotifyConnected)
          FilledButton(
            onPressed: _connect,
            child: const Text('Connect Spotify'),
          )
        else ...[
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Play on',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: 'Refresh devices',
                onPressed: _loadDevices,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          if (_devices == null)
            const LinearProgressIndicator()
          else if (_devices!.isEmpty)
            // Spotify only lists devices that have the app open.
            const Text(
              'No devices found. Open Spotify on a device, then refresh.',
            )
          else
            for (final d in _devices!)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(_icon(d.type)),
                title: Text(d.name),
                subtitle: d.isActive ? const Text('Playing now') : null,
                trailing: d.isActive
                    ? const Icon(Icons.graphic_eq, size: 20)
                    : null,
                onTap: () =>
                    _run(() => c.playOnSpotifyDevice(d.id), makeActive: d.id),
              ),
          const SizedBox(height: 12),
          const Text(
            'Playlists',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          FutureBuilder<List<SpotifyPlaylist>>(
            future: _playlists,
            builder: (context, snap) => Column(
              children: [
                for (final p in snap.data ?? const <SpotifyPlaylist>[])
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: p.imageUrl == null
                        ? const Icon(Icons.queue_music)
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.network(
                              p.imageUrl!,
                              width: 44,
                              height: 44,
                            ),
                          ),
                    title: Text(
                      p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => _run(() => c.playSpotifyPlaylist(p.uri)),
                  ),
              ],
            ),
          ),
        ],
        // reading other apps' music needs Android's notification access
        if (defaultTargetPlatform != TargetPlatform.iOS) ...[
          const Divider(height: 32),
          const Text('This phone (any player)', style: heading),
          const SizedBox(height: 8),
          const Text('Needs Notification access to read the playing track.'),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: c.openNotificationAccess,
            child: const Text('Open Notification access settings'),
          ),
        ],
        if (widget.onAllSettings != null) ...[
          const Divider(height: 32),
          TextButton(
            onPressed: widget.onAllSettings,
            child: const Text('All settings'),
          ),
        ],
      ],
    );
  }
}

/// Volume of the Spotify device that is playing (a Mac, a speaker, a TV...).
/// Sending is throttled while dragging so it follows your finger without
/// flooding Spotify, and the slider keeps your value instead of snapping back.
class SpotifyVolume extends StatefulWidget {
  const SpotifyVolume({
    super.key,
    required this.controller,
    this.compact = false,
    this.onTouch,
  });

  final StandbyController controller;

  /// A slim dark bar for laying over the music card: no device name.
  final bool compact;

  /// Called on every touch/change (the card uses it to keep the bar open).
  final VoidCallback? onTouch;

  @override
  State<SpotifyVolume> createState() => _SpotifyVolumeState();
}

class _SpotifyVolumeState extends State<SpotifyVolume> {
  StandbyController get c => widget.controller;
  SpotifyDevice? _device; // the device playing now
  double? _drag; // finger position while dragging
  int _beforeMute = 40;
  int? _pending;
  Timer? _throttle;
  Timer? _poll;
  String? _lastSource; // "Spotify · <device>": changes when playback moves

  // Playback moved to another device (the card notices within a second or two):
  // the volume card must follow it right away, not on the next 8 s look.
  void _onController() {
    final now = c.snapshots.nowPlaying.source;
    if (now == _lastSource) return;
    _lastSource = now;
    if (_drag == null) _refresh();
  }

  @override
  void initState() {
    super.initState();
    _refresh();
    _lastSource = c.snapshots.nowPlaying.source;
    c.addListener(_onController);
    // follow changes made on the device itself, but never while dragging
    _poll = Timer.periodic(const Duration(seconds: 8), (_) {
      if (_drag == null) _refresh();
    });
  }

  @override
  void dispose() {
    c.removeListener(_onController);
    _poll?.cancel();
    _throttle?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!c.spotifyConnected) return;
    final list = await c.spotifyDevices();
    if (!mounted || _drag != null) return;
    setState(() {
      _device = list.where((d) => d.isActive).firstOrNull;
    });
  }

  void _send() {
    final d = _device, p = _pending;
    if (d == null || p == null) return;
    _pending = null;
    c.setSpotifyVolume(d.id, p).then((ok) {
      if (!ok && mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text(c.musicError ?? 'Could not set volume')),
          );
      }
    });
  }

  void _queue(int percent) {
    _pending = percent;
    if (_throttle?.isActive ?? false) return; // the timer sends the latest one
    _send();
    _throttle = Timer(const Duration(milliseconds: 250), () {
      if (_pending != null) _send();
    });
  }

  void _set(int percent) {
    final d = _device!;
    setState(() {
      _device = SpotifyDevice(
        d.id,
        d.name,
        d.type,
        d.isActive,
        volume: percent,
      );
      _drag = null;
    });
    _pending = percent;
    _send();
  }

  @override
  Widget build(BuildContext context) {
    final d = _device;
    if (d == null) return const SizedBox.shrink();
    final locked = d.volume == null;
    final value = (_drag ?? d.volume?.toDouble() ?? 0).clamp(0.0, 100.0);
    final level = value.round();
    if (widget.compact) {
      return Container(
        padding: const EdgeInsets.fromLTRB(4, 0, 16, 0),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: level == 0 ? 'Unmute' : 'Mute',
              onPressed: locked
                  ? null
                  : () {
                      widget.onTouch?.call();
                      if (level > 0) _beforeMute = level;
                      _set(level > 0 ? 0 : _beforeMute);
                    },
              icon: Icon(
                level == 0
                    ? Icons.volume_off_rounded
                    : level < 50
                    ? Icons.volume_down_rounded
                    : Icons.volume_up_rounded,
                color: Colors.white,
              ),
            ),
            Expanded(
              child: locked
                  ? Text(
                      "${d.name} doesn't allow volume control",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70),
                    )
                  : SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 6,
                        activeTrackColor: Colors.white,
                        inactiveTrackColor: Colors.white24,
                        thumbColor: Colors.white,
                        overlayShape: SliderComponentShape.noOverlay,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 9,
                        ),
                      ),
                      child: Slider(
                        value: value,
                        max: 100,
                        onChanged: (v) {
                          widget.onTouch?.call();
                          setState(() => _drag = v);
                          _queue(v.round());
                        },
                        onChangeEnd: (v) {
                          widget.onTouch?.call();
                          _throttle?.cancel();
                          _set(v.round());
                          Future.delayed(const Duration(seconds: 2), _refresh);
                        },
                      ),
                    ),
            ),
            if (!locked)
              SizedBox(
                width: 44,
                child: Text(
                  '$level%',
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: level == 0 ? 'Unmute' : 'Mute',
            onPressed: locked
                ? null
                : () {
                    if (level > 0) _beforeMute = level;
                    _set(level > 0 ? 0 : _beforeMute);
                  },
            icon: Icon(
              level == 0
                  ? Icons.volume_off_rounded
                  : level < 50
                  ? Icons.volume_down_rounded
                  : Icons.volume_up_rounded,
            ),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        locked
                            ? "${d.name} doesn't allow volume control here"
                            : 'Volume · ${d.name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (!locked)
                      Text(
                        '$level%',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 8,
                    overlayShape: SliderComponentShape.noOverlay,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 10,
                    ),
                  ),
                  child: Slider(
                    value: value,
                    max: 100,
                    onChanged: locked
                        ? null
                        : (v) {
                            setState(() => _drag = v);
                            _queue(v.round());
                          },
                    onChangeEnd: locked
                        ? null
                        : (v) {
                            _throttle?.cancel();
                            _set(v.round());
                            Future.delayed(
                              const Duration(seconds: 2),
                              _refresh,
                            );
                          },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
