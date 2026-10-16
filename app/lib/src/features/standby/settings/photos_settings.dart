import 'package:flutter/material.dart';

import '../../../domain/standby_models.dart';
import '../../../services/photo_service.dart';
import '../../../state/standby_controller.dart';
import '../widgets/dock.dart';
import '../widgets/photos_card.dart';
import 'controls.dart';

/// Where the slideshow's pictures come from, and how it plays: a live preview
/// on top, the two sources as choices, then the timing.
class PhotosBody extends StatefulWidget {
  const PhotosBody({super.key, required this.controller});

  final StandbyController controller;

  @override
  State<PhotosBody> createState() => _PhotosBodyState();
}

class _PhotosBodyState extends State<PhotosBody> {
  List<PhotoAlbum>? _albums; // shown after tapping "Photos album"
  bool _loading = false;

  StandbyController get c => widget.controller;

  Future<void> _showAlbums() async {
    if (_albums != null) {
      setState(() => _albums = null);
      return;
    }
    setState(() => _loading = true);
    final list = await c.photoAlbums();
    if (!mounted) return;
    setState(() {
      _albums = list;
      _loading = false;
    });
  }

  String _caption(StandbySettings s) {
    final name = s.photoSource == PhotoSource.library
        ? s.photoAlbumName
        : s.photoFolder.split('/').where((p) => p.isNotEmpty).lastOrNull ?? '';
    final n = c.photoFeed?.length;
    return n == null ? name : '$name · $n pictures';
  }

  // the card as it plays, small; or a quiet frame until a source is chosen
  Widget _preview(StandbySettings s) {
    final live = c.photoFeed != null;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (live)
                IgnorePointer(
                  child: PhotosCard(
                    feed: c.photoFeed,
                    settings: s,
                    compact: true,
                  ),
                )
              else
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFFFF9F0A).withValues(alpha: 0.35),
                        const Color(0xFF5E5CE6).withValues(alpha: 0.35),
                      ],
                    ),
                  ),
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.photo_library_rounded,
                          size: 40,
                          color: Colors.white70,
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Choose where the pictures come from',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ),
              if (live && _caption(s).isNotEmpty)
                Positioned(
                  left: 12,
                  bottom: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      _caption(s),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // one source: a coloured badge, its name and what is chosen, a check when it
  // is the one in use
  Widget _source({
    required IconData icon,
    required Color color,
    required String title,
    required String detail,
    required bool selected,
    required VoidCallback onTap,
    bool busy = false,
    bool open = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Material(
      color: Colors.white.withValues(alpha: selected ? 0.11 : 0.06),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        splashFactory: NoSplash.splashFactory,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white60),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (busy)
                const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (selected)
                Icon(
                  Icons.check_circle_rounded,
                  color: Theme.of(context).colorScheme.primary,
                )
              else
                AnimatedRotation(
                  turns: open ? 0.25 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white38,
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _albumList(StandbySettings s) {
    final albums = _albums!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
        ),
        child: albums.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  c.photoAccess == PhotoAccess.granted
                      ? 'No albums with pictures.'
                      : 'Photos access is off. Allow it in System Settings > '
                            'Privacy & Security > Photos.',
                  style: const TextStyle(color: Colors.white70),
                ),
              )
            : Column(
                children: [
                  for (var i = 0; i < albums.length; i++) ...[
                    if (i > 0)
                      const Divider(
                        height: 1,
                        indent: 16,
                        color: Colors.white12,
                      ),
                    InkWell(
                      splashFactory: NoSplash.splashFactory,
                      onTap: () async {
                        if (await c.choosePhotoAlbum(albums[i])) {
                          setState(() => _albums = null);
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                albums[i].name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 16),
                              ),
                            ),
                            Text(
                              '${albums[i].count}',
                              style: const TextStyle(color: Colors.white54),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 22,
                              child: s.photoAlbumId == albums[i].id
                                  ? Icon(
                                      Icons.check_rounded,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    )
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final s = c.settings;
        void set(StandbySettings v) => c.updateSettings(v);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _preview(s),
            SettingsSection(
              title: 'Source',
              scope: 'Photos',
              nested: true,
              first: true,
              subtitle:
                  'Read where they are, one at a time. Nothing is copied, '
                  'changed or sent anywhere.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (PhotoService.libraryUsable)
                    _source(
                      icon: Icons.photo_library_rounded,
                      color: const Color(0xFFFF9F0A),
                      title: 'Photos album',
                      detail:
                          s.photoSource == PhotoSource.library &&
                              s.photoAlbumName.isNotEmpty
                          ? s.photoAlbumName
                          : 'An album from the Photos app',
                      selected:
                          s.photoSource == PhotoSource.library &&
                          s.photoAlbumName.isNotEmpty &&
                          _albums == null,
                      busy: _loading,
                      open: _albums != null,
                      onTap: _showAlbums,
                    ),
                  if (_albums != null) _albumList(s),
                  if (PhotoService.folderUsable)
                    _source(
                      icon: Icons.folder_rounded,
                      color: const Color(0xFF0A84FF),
                      title: 'Folder',
                      detail:
                          s.photoSource == PhotoSource.folder &&
                              s.photoFolder.isNotEmpty
                          ? s.photoFolder
                          : 'Pictures in a folder of this computer',
                      selected:
                          s.photoSource == PhotoSource.folder &&
                          s.photoFolder.isNotEmpty,
                      onTap: c.choosePhotoFolder,
                    ),
                  if (c.photoProblem != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, bottom: 8),
                      child: Text(
                        c.photoProblem!,
                        style: const TextStyle(color: Colors.orangeAccent),
                      ),
                    ),
                ],
              ),
            ),
            SettingsSection(
              title: 'Playing',
              scope: 'Photos',
              nested: true,
              first: true,
              child: Column(
                children: [
                  EnumPicker<int>(
                    label: 'Each picture for',
                    value: s.photoSeconds,
                    values: const [5, 10, 15, 30, 60],
                    display: (v) => '$v seconds',
                    onChanged: (v) => set(s.copyWith(photoSeconds: v)),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: s.photoFill,
                    onChanged: (v) => set(s.copyWith(photoFill: v)),
                    title: const Text('Fill the card'),
                    subtitle: const Text(
                      'Off: the whole picture shows, with black around it.',
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The Photos card's settings in the dock.
class PhotosSettings extends StatelessWidget {
  const PhotosSettings({
    super.key,
    required this.controller,
    required this.onAll,
  });

  final StandbyController controller;
  final VoidCallback onAll;

  @override
  Widget build(BuildContext context) => ListView(
    padding: dockPadding,
    children: [
      PhotosBody(controller: controller),
      const Text(
        'Tip: swipe up or down on the card, or press the up and down arrows, '
        'for the next or last picture.',
        style: TextStyle(color: Colors.white54),
      ),
      AllSettingsButton(onPressed: onAll),
    ],
  );
}
