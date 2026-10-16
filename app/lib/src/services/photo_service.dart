import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';

/// Whether Hushdock may read the Photos library.
enum PhotoAccess { unknown, granted, denied, unsupported }

/// A Photos album you can choose.
class PhotoAlbum {
  const PhotoAlbum({required this.id, required this.name, required this.count});
  final String id;
  final String name;
  final int count;
}

/// The pictures of one source, in the order they will play (shuffled once).
/// Pictures are read one at a time, only when they are about to show, at about
/// the size they are shown: nothing is copied, uploaded or kept.
abstract class PhotoFeed {
  int get length;

  /// the picture at [index], scaled to fit [px] pixels; null if it cannot be
  /// read any more (deleted, an unreadable file)
  Future<Uint8List?> bytes(int index, int px);
}

const _imageExtensions = {
  'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'heif', //
};

/// Pictures in a folder (and the folders inside it, down to a limit).
class FolderFeed implements PhotoFeed {
  FolderFeed._(this._files);

  final List<File> _files;

  /// null when the folder cannot be read
  static FolderFeed? open(String path, {int limit = 2000, int? seed}) {
    try {
      final found = <File>[];
      for (final e in Directory(path).listSync(recursive: true)) {
        if (e is! File) continue;
        final dot = e.path.lastIndexOf('.');
        if (dot < 0) continue;
        if (!_imageExtensions.contains(
          e.path.substring(dot + 1).toLowerCase(),
        )) {
          continue;
        }
        // hidden files ("._photo.jpg" copies, the Photos library's internals)
        if (e.uri.pathSegments.last.startsWith('.')) continue;
        found.add(e);
        if (found.length >= limit) break;
      }
      found.shuffle(math.Random(seed));
      return FolderFeed._(found);
    } on FileSystemException {
      return null;
    }
  }

  @override
  int get length => _files.length;

  @override
  Future<Uint8List?> bytes(int index, int px) async {
    try {
      return await _files[index % _files.length].readAsBytes();
    } on FileSystemException {
      return null;
    }
  }
}

/// Pictures of one Photos album (Mac, iPhone, Android).
class LibraryFeed implements PhotoFeed {
  LibraryFeed._(this._assets);

  final List<AssetEntity> _assets;

  static Future<LibraryFeed?> open(String albumId, {int limit = 500}) async {
    try {
      final album = await AssetPathEntity.fromId(
        albumId,
        type: RequestType.image,
      );
      final count = await album.assetCountAsync;
      if (count == 0) return LibraryFeed._(const []);
      final assets = await album.getAssetListRange(
        start: 0,
        end: math.min(count, limit),
      );
      return LibraryFeed._(assets..shuffle());
    } catch (_) {
      return null;
    }
  }

  @override
  int get length => _assets.length;

  @override
  Future<Uint8List?> bytes(int index, int px) => _assets[index % _assets.length]
      .thumbnailDataWithSize(ThumbnailSize(px, px), quality: 88);
}

/// Choosing and reading the pictures of the slideshow. Both ways are
/// read-only: the Photos permission is the system's own, and a Mac keeps the
/// right to read the one folder you pick (a security-scoped bookmark), nothing
/// else.
class PhotoService {
  PhotoService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('standby_pro/photos');

  final MethodChannel _channel;

  static bool get libraryUsable =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  static bool get folderUsable =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);

  static PhotoAccess _access(PermissionState s) => switch (s) {
    PermissionState.authorized ||
    PermissionState.limited => PhotoAccess.granted,
    PermissionState.notDetermined => PhotoAccess.unknown,
    _ => PhotoAccess.denied,
  };

  Future<PhotoAccess> libraryAccess() async {
    if (!libraryUsable) return PhotoAccess.unsupported;
    try {
      // a status check only: it never shows the question
      return _access(
        await PhotoManager.getPermissionState(
          requestOption: const PermissionRequestOption(),
        ),
      );
    } catch (_) {
      return PhotoAccess.denied;
    }
  }

  /// Shows the system's question (once); the answer.
  Future<PhotoAccess> requestLibrary() async {
    if (!libraryUsable) return PhotoAccess.unsupported;
    try {
      return _access(await PhotoManager.requestPermissionExtend());
    } catch (_) {
      return PhotoAccess.denied;
    }
  }

  Future<List<PhotoAlbum>> albums() async {
    if (!libraryUsable) return const [];
    try {
      final all = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        hasAll: false,
      );
      return [
        for (final a in all)
          PhotoAlbum(id: a.id, name: a.name, count: await a.assetCountAsync),
      ]..removeWhere((a) => a.count == 0);
    } catch (_) {
      return const [];
    }
  }

  Future<PhotoFeed?> libraryFeed(String albumId) => LibraryFeed.open(albumId);

  /// A Mac needs its [bookmark] (from [pickFolder]) to open the folder again
  /// after a restart; the answer is the folder's path, readable from now on.
  Future<PhotoFeed?> folderFeed(String path, {String bookmark = ''}) async {
    var readable = path;
    if (defaultTargetPlatform == TargetPlatform.macOS && bookmark.isNotEmpty) {
      try {
        readable =
            await _channel.invokeMethod<String>('openFolder', {
              'bookmark': bookmark,
            }) ??
            '';
      } on MissingPluginException {
        readable = path;
      } on PlatformException {
        return null;
      }
    }
    return readable.isEmpty ? null : FolderFeed.open(readable);
  }

  /// The system's folder question; null if cancelled or not available.
  Future<({String path, String bookmark})?> pickFolder() async {
    if (!folderUsable) return null;
    try {
      if (defaultTargetPlatform == TargetPlatform.macOS) {
        final r = await _channel.invokeMapMethod<String, String>('pickFolder');
        if (r == null || (r['path'] ?? '').isEmpty) return null;
        return (path: r['path']!, bookmark: r['bookmark'] ?? '');
      }
      final path = await FilePicker.getDirectoryPath();
      return path == null ? null : (path: path, bookmark: '');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
