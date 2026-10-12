/// The tiles the Summary panel can show. The music tile is double size: it
/// takes a whole column (or row, in portrait); every other tile is small, two
/// to a column. Any of them can be added or removed.
enum SummaryTile { here, there, date, weather, timer, music }

/// Which tiles the Summary panel shows, and in what order. The tiles are laid
/// out in that order: small ones two to a column, music alone in its own.
/// There is room for three columns, so adding a tile only works while it
/// still fits. Stored in the settings as one short string.
class SummaryLayout {
  const SummaryLayout([
    this.tiles = const [
      SummaryTile.here,
      SummaryTile.there,
      SummaryTile.date,
      SummaryTile.weather,
      SummaryTile.music,
    ],
  ]);

  static const standard = SummaryLayout();

  /// the most columns (rows, in portrait) the panel has room for
  static const maxColumns = 3;

  final List<SummaryTile> tiles;

  /// "v2:here,there,date,weather,music"
  String encode() => 'v2:${tiles.map((t) => t.name).join(',')}';

  /// Reads [encode]'s output, and the older "here,there,date,weather;2" form.
  /// Anything unreadable gives [standard], so a bad or old saved value can
  /// never break the screen.
  factory SummaryLayout.parse(String? text) {
    try {
      final t = text ?? '';
      final List<SummaryTile> tiles;
      if (t.startsWith('v2:')) {
        final body = t.substring(3);
        tiles = body.isEmpty
            ? <SummaryTile>[]
            : [
                for (final n in body.split(','))
                  SummaryTile.values.firstWhere((v) => v.name == n),
              ];
      } else {
        // before: four small tiles and which column the music took (0-2)
        final parts = t.split(';');
        final small = [
          for (final n in parts[0].split(','))
            SummaryTile.values.firstWhere((v) => v.name == n),
        ];
        final column = int.parse(parts[1]);
        if (small.length != 4 || column < 0 || column > 2) return standard;
        tiles = [...small]..insert(column * 2, SummaryTile.music);
      }
      final layout = SummaryLayout(tiles);
      if (tiles.toSet().length != tiles.length || !layout.fits) {
        return standard;
      }
      return layout;
    } catch (_) {
      return standard;
    }
  }

  /// [items] in columns: the big one alone, the others two by two (a lone
  /// one fills its column). Works for any kind of item, so the panel can lay
  /// out its "+" placeholder the same way.
  static List<List<T>> pack<T>(List<T> items, bool Function(T) isBig) {
    final cols = <List<T>>[];
    var open = <T>[];
    for (final item in items) {
      if (isBig(item)) {
        if (open.isNotEmpty) cols.add(open);
        open = <T>[];
        cols.add([item]);
      } else {
        open.add(item);
        if (open.length == 2) {
          cols.add(open);
          open = <T>[];
        }
      }
    }
    if (open.isNotEmpty) cols.add(open);
    return cols;
  }

  /// The tiles in each column.
  List<List<SummaryTile>> get columns =>
      pack(tiles, (t) => t == SummaryTile.music);

  /// Whether everything fits in [maxColumns] columns.
  bool get fits => columns.length <= maxColumns;

  /// The tiles that are not on the panel.
  List<SummaryTile> get missing => [
    for (final t in SummaryTile.values)
      if (!tiles.contains(t)) t,
  ];

  /// With [tile] added (at the end if it fits there, otherwise at the first
  /// place, from the end, where it does), or null when there is no room.
  SummaryLayout? added(SummaryTile tile) {
    if (tiles.contains(tile)) return this;
    for (var at = tiles.length; at >= 0; at--) {
      final next = SummaryLayout([...tiles]..insert(at, tile));
      if (next.fits) return next;
    }
    return null;
  }

  /// Without [tile].
  SummaryLayout without(SummaryTile tile) => SummaryLayout([
    for (final t in tiles)
      if (t != tile) t,
  ]);

  /// [a] and [b] trade places (or stay, when that would not fit).
  SummaryLayout swap(SummaryTile a, SummaryTile b) {
    final list = [...tiles];
    final i = list.indexOf(a), j = list.indexOf(b);
    if (i < 0 || j < 0 || i == j) return this;
    list[i] = b;
    list[j] = a;
    final next = SummaryLayout(list);
    return next.fits ? next : this;
  }

  @override
  bool operator ==(Object other) =>
      other is SummaryLayout && other.encode() == encode();

  @override
  int get hashCode => encode().hashCode;
}
