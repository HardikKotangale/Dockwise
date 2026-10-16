import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../state/standby_controller.dart';

const _green = Color(0xFF1DB954);

/// A guide to making your own free Spotify app and pasting its Client ID, so
/// search, playlists, the queue and devices work. Not needed to see and
/// control what the Spotify app is playing.
class SpotifySetupPage extends StatefulWidget {
  const SpotifySetupPage({super.key, required this.controller});

  final StandbyController controller;

  @override
  State<SpotifySetupPage> createState() => _SpotifySetupPageState();
}

class _SpotifySetupPageState extends State<SpotifySetupPage> {
  static const dashboard = 'https://developer.spotify.com/dashboard';
  static const redirect = 'hushdock://spotify-callback';
  static const appName = 'Hushdock';
  static const appDescription =
      'Hushdock is a clock and now-playing display for desktop and mobile. '
      'It shows the track currently playing on the signed-in Spotify account '
      'and provides playback controls, search and device selection. '
      'Personal, non-commercial use only.';

  final _id = TextEditingController();
  String? _error;
  bool _saved = false; // just saved: show the check, then Sign in
  bool _busy = false;
  bool _confirmRemove = false;

  StandbyController get c => widget.controller;

  bool get _phone =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;

  // Esc goes back (the page is a full-screen route above the display)
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent || e.logicalKey != LogicalKeyboardKey.escape) {
      return false;
    }
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return false;
    Navigator.of(context).pop();
    return true;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _id.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text != null && mounted) {
      setState(() {
        _id.text = text.length > 32 ? text.substring(0, 32) : text;
        _error = null;
      });
    }
  }

  Future<void> _save() async {
    final ok = await c.saveSpotifyClientId(_id.text);
    if (!mounted) return;
    setState(() {
      _saved = ok;
      _error = ok
          ? null
          : 'This is not a valid Client ID. A Client ID has 32 characters '
                '(0-9 and a-f). Copy it again from your app\'s Settings page.';
      if (ok) _id.clear();
    });
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await c.connectSpotify();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = ok
          ? null
          : 'Sign-in was not completed. Check step 3 (the redirect URI) and '
                'step 5 (your account under User management), then try again.';
    });
    if (ok) {
      // let the check show for a moment, then the guide is done
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _signOut() async {
    await c.disconnectSpotify();
    if (!mounted) return;
    setState(() {
      _saved = true;
    });
  }

  Future<void> _remove() async {
    if (!_confirmRemove) {
      setState(() => _confirmRemove = true);
      Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _confirmRemove = false);
      });
      return;
    }
    await c.removeSpotifyClientId();
    if (!mounted) return;
    setState(() {
      _confirmRemove = false;
      _saved = false;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasOwn = c.spotifyOwnClientId;
    final connected = c.spotifyConnected;
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: Theme.of(context).colorScheme.copyWith(primary: _green),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: const Text('Connect your Spotify account'),
        ),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
                children: [
                  Text(
                    'To search, browse playlists and choose a playback device, '
                    'Hushdock connects to Spotify through an app registered '
                    'under your own Spotify account. Setup takes about five '
                    'minutes and is done once. Spotify Premium is required.',
                    style: TextStyle(
                      height: 1.45,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _StepCard(
                    n: 1,
                    title: 'Open the Spotify Developer Dashboard',
                    body: _phone
                        ? 'Sign in with the Spotify account you listen with. '
                              'Steps 1 to 5 are easier on a computer.'
                        : 'Sign in with the Spotify account you listen with.',
                    child: Wrap(
                      spacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: () => c.openLink(dashboard),
                          icon: const Icon(Icons.open_in_new_rounded, size: 18),
                          label: const Text('Open Dashboard'),
                        ),
                        _CopyButton(label: 'Copy link', value: dashboard),
                      ],
                    ),
                  ),
                  const _StepCard(
                    n: 2,
                    title: 'Create an app',
                    body: 'Choose "Create app" and enter the details below.',
                    child: Column(
                      children: [
                        _CopyField(label: 'App name', value: appName),
                        SizedBox(height: 8),
                        _CopyField(
                          label: 'App description',
                          value: appDescription,
                        ),
                      ],
                    ),
                  ),
                  const _StepCard(
                    n: 3,
                    title: 'Add the redirect URI',
                    body:
                        'Under "Redirect URIs", paste the value below and '
                        'choose Add. Spotify uses it to return you to '
                        'Hushdock after you sign in.',
                    child: _CopyField(label: 'Redirect URI', value: redirect),
                  ),
                  _StepCard(
                    n: 4,
                    title: 'Select the API',
                    body:
                        'Select "Web API" only, accept the terms and choose '
                        'Save. Leave the other options unselected.',
                  ),
                  _StepCard(
                    n: 5,
                    title: 'Add your account',
                    body:
                        'Open your app, then Settings > User management. Add '
                        'your name and the email address of your Spotify '
                        'account so that Spotify allows you to sign in.',
                  ),
                  _StepCard(
                    n: 6,
                    title: 'Enter your Client ID',
                    body:
                        'On the same Settings page, copy the Client ID and '
                        'paste it below. Never use the Client secret.',
                    highlight: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (hasOwn)
                          // saved: the ID is hidden, only its end shows
                          InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Client ID (stored on this device)',
                              prefixIcon: Icon(
                                Icons.lock_rounded,
                                color: _green,
                                size: 20,
                              ),
                            ),
                            child: Text(
                              c.spotifyClientIdMasked,
                              style: const TextStyle(
                                letterSpacing: 1.5,
                                fontFamily: 'Menlo',
                                fontSize: 13,
                              ),
                            ),
                          )
                        else
                          TextField(
                            controller: _id,
                            autocorrect: false,
                            enableSuggestions: false,
                            onChanged: (_) {
                              if (_error != null) setState(() => _error = null);
                            },
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp('[0-9a-fA-F]'),
                              ),
                              LengthLimitingTextInputFormatter(32),
                            ],
                            decoration: InputDecoration(
                              labelText: 'Client ID',
                              helperText: '32 characters (0-9, a-f)',
                              suffixIcon: IconButton(
                                tooltip: 'Paste',
                                onPressed: _paste,
                                icon: const Icon(Icons.content_paste_rounded),
                              ),
                            ),
                          ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 12,
                          runSpacing: 10,
                          children: [
                            if (!hasOwn)
                              FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: _green,
                                  foregroundColor: Colors.black,
                                ),
                                onPressed: _save,
                                child: const Text('Save'),
                              )
                            else ...[
                              _Appear(
                                show: true,
                                child: connected
                                    ? OutlinedButton.icon(
                                        onPressed: _signOut,
                                        icon: const Icon(
                                          Icons.logout_rounded,
                                          size: 18,
                                        ),
                                        label: const Text('Sign out'),
                                      )
                                    : FilledButton.icon(
                                        style: FilledButton.styleFrom(
                                          backgroundColor: _green,
                                          foregroundColor: Colors.black,
                                        ),
                                        onPressed: _busy ? null : _signIn,
                                        icon: _busy
                                            ? const SizedBox.square(
                                                dimension: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: Colors.black,
                                                    ),
                                              )
                                            : const Icon(
                                                Icons.login_rounded,
                                                size: 18,
                                              ),
                                        label: Text(
                                          _busy
                                              ? 'Signing in…'
                                              : 'Sign in with Spotify',
                                        ),
                                      ),
                              ),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFFFF6B6B),
                                  side: const BorderSide(
                                    color: Color(0xFFFF6B6B),
                                  ),
                                ),
                                onPressed: _remove,
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  size: 18,
                                ),
                                label: Text(
                                  _confirmRemove
                                      ? 'Tap again to confirm'
                                      : 'Remove',
                                ),
                              ),
                            ],
                          ],
                        ),
                        _Status(
                          saved: _saved && !connected,
                          signedIn: connected,
                          error: _error,
                          alreadySaved: hasOwn && !connected && !_saved,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.lock_outline_rounded,
                          size: 20,
                          color: _green,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Your Client ID and sign-in are stored securely on '
                            'this device. You can remove them at any time.',
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.45,
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One numbered step in its own rounded card.
class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.n,
    required this.title,
    required this.body,
    this.child,
    this.highlight = false,
  });

  final int n;
  final String title;
  final String body;
  final Widget? child;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: highlight ? 0.08 : 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlight ? _green.withValues(alpha: 0.6) : Colors.transparent,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: _green,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$n',
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: TextStyle(
                    height: 1.4,
                    color: Colors.white.withValues(alpha: 0.72),
                  ),
                ),
                if (child != null) ...[const SizedBox(height: 12), child!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A value in a box with a copy button that flips to a check for a moment.
class _CopyField extends StatelessWidget {
  const _CopyField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 11, color: Colors.white54),
                ),
                const SizedBox(height: 2),
                SelectableText(
                  value,
                  style: const TextStyle(fontSize: 14, height: 1.35),
                ),
              ],
            ),
          ),
          _CopyButton(value: value),
        ],
      ),
    );
  }
}

class _CopyButton extends StatefulWidget {
  const _CopyButton({required this.value, this.label});

  final String value;
  final String? label; // null: an icon

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _done = false;
  Timer? _t;

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.value));
    if (!mounted) return;
    setState(() => _done = true);
    _t?.cancel();
    _t = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _done = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final icon = AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: Icon(
        _done ? Icons.check_rounded : Icons.copy_rounded,
        key: ValueKey(_done),
        size: 18,
        color: _done ? _green : null,
      ),
    );
    if (widget.label == null) {
      return IconButton(
        tooltip: _done ? 'Copied' : 'Copy',
        onPressed: _copy,
        icon: icon,
      );
    }
    return TextButton.icon(
      onPressed: _copy,
      icon: icon,
      label: Text(_done ? 'Copied' : widget.label!),
    );
  }
}

/// Fades and slides its child in when [show] turns on.
class _Appear extends StatelessWidget {
  const _Appear({required this.show, required this.child});

  final bool show;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      alignment: Alignment.centerLeft,
      child: show
          ? TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 380),
              curve: Curves.easeOutBack,
              builder: (context, t, child) => Opacity(
                opacity: t.clamp(0, 1),
                child: Transform.translate(
                  offset: Offset(-16 * (1 - t), 0),
                  child: child,
                ),
              ),
              child: child,
            )
          : const SizedBox.shrink(),
    );
  }
}

/// The line under the buttons: a check that pops in when saved, then signed in.
class _Status extends StatelessWidget {
  const _Status({
    required this.saved,
    required this.signedIn,
    required this.error,
    required this.alreadySaved,
  });

  final bool saved;
  final bool signedIn;
  final String? error;
  final bool alreadySaved;

  @override
  Widget build(BuildContext context) {
    final (IconData, Color, String)? line = error != null
        ? (Icons.error_outline_rounded, const Color(0xFFFF6B6B), error!)
        : signedIn
        ? (
            Icons.check_circle_rounded,
            _green,
            'Signed in. Search, playlists and devices are available.',
          )
        : saved
        ? (
            Icons.check_circle_rounded,
            _green,
            'Client ID saved. You can now sign in.',
          )
        : alreadySaved
        ? (Icons.lock_rounded, _green, 'A Client ID is stored on this device.')
        : null;
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topLeft,
      child: line == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(top: 14),
              child: TweenAnimationBuilder<double>(
                key: ValueKey(line.$3),
                tween: Tween(begin: 0.6, end: 1),
                duration: const Duration(milliseconds: 420),
                curve: Curves.elasticOut,
                builder: (context, t, child) => Transform.scale(
                  scale: t,
                  alignment: Alignment.centerLeft,
                  child: child,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(line.$1, color: line.$2, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        line.$3,
                        style: TextStyle(
                          color: line.$2,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
