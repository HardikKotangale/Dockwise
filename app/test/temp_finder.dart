import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The big temperature on a weather card, by its number ("19"): the degree
/// sign is a separate small widget beside it, so the text is just the number.
Finder bigTemp(String number) => find.byWidgetPredicate(
  (w) =>
      w is Text &&
      w.textSpan != null &&
      w.textSpan!.toPlainText(includePlaceholders: false) == number,
);
