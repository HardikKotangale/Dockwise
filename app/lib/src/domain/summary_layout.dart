/// The four small tiles of the Summary panel. The music tile is separate: it
/// always takes a whole column (or row, in portrait).
enum SummaryTile { here, there, date, weather }

/// Where the Summary panel's tiles sit: the order of the four small tiles
/// (two per column, read in order) and which of the three columns the music
/// tile takes. Stored in the settings as one short string.
class SummaryLayout {
  const SummaryLayout({
    this.tiles = const [
      SummaryTile.here,
      SummaryTile.there,
      SummaryTile.date,
      SummaryTile.weather,
    ],
    this.musicColumn = 2,
  });

  static const standard = SummaryLayout();

  final List<SummaryTile> tiles;

  /// 0, 1 or 2: left, middle, right (top, middle, bottom in portrait)
  final int musicColumn;

  /// "here,there,date,weather;2"
  String encode() => '${tiles.map((t) => t.name).join(',')};$musicColumn';

  /// Reads [encode]'s output. Anything unreadable gives [standard], so a bad
  /// or old saved value can never break the screen.
  factory SummaryLayout.parse(String? text) {
    try {
      final parts = (text ?? '').split(';');
      final tiles = [
        for (final n in parts[0].split(','))
          SummaryTile.values.firstWhere((t) => t.name == n),
      ];
      final column = int.parse(parts[1]);
      if (tiles.length != SummaryTile.values.length ||
          tiles.toSet().length != tiles.length ||
          column < 0 ||
          column > 2) {
        return standard;
      }
      return SummaryLayout(tiles: tiles, musicColumn: column);
    } catch (_) {
      return standard;
    }
  }

  /// The two small tiles in each column: null where the music tile is.
  List<List<SummaryTile>?> get columns {
    var next = 0;
    return [
      for (var c = 0; c < 3; c++)
        if (c == musicColumn) null else [tiles[next++], tiles[next++]],
    ];
  }

  /// Which column [tile] is in.
  int columnOf(SummaryTile tile) {
    final cols = columns;
    for (var c = 0; c < 3; c++) {
      if (cols[c]?.contains(tile) ?? false) return c;
    }
    return 0;
  }

  /// [a] and [b] trade places.
  SummaryLayout swap(SummaryTile a, SummaryTile b) {
    final list = [...tiles];
    final i = list.indexOf(a), j = list.indexOf(b);
    if (i < 0 || j < 0 || i == j) return this;
    list[i] = b;
    list[j] = a;
    return SummaryLayout(tiles: list, musicColumn: musicColumn);
  }

  /// The music tile moves to [column]; the tiles keep their order.
  SummaryLayout withMusicColumn(int column) =>
      SummaryLayout(tiles: tiles, musicColumn: column.clamp(0, 2));

  @override
  bool operator ==(Object other) =>
      other is SummaryLayout && other.encode() == encode();

  @override
  int get hashCode => encode().hashCode;
}
