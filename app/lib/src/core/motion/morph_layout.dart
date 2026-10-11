import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';

import 'motion.dart';

/// A time laid out either on one line (hours : minutes, then a trailing part
/// like seconds or AM/PM) or in a stack (hours over minutes over the trailing
/// part). When [stacked] changes the parts do not jump: they glide, on a
/// spring, from one arrangement to the other, the colon folding away.
class MorphLayout extends StatefulWidget {
  const MorphLayout({
    super.key,
    required this.stacked,
    required this.hours,
    required this.minutes,
    this.separator,
    this.trailing,
    this.suffix,
    this.rowGap = 0,
    this.stackGap = 0,
    this.suffixGap = 10,
  });

  final bool stacked;
  final Widget hours;
  final Widget minutes;

  /// the colon: shown on one line, folded away when stacked
  final Widget? separator;

  /// seconds or AM/PM: after the minutes, or under them when stacked
  final Widget? trailing;

  /// AM/PM. It sits at the end of the last line, at its bottom edge, hanging
  /// out to the right so it never pushes the numbers off their centre.
  final Widget? suffix;

  /// space between the parts on one line / in a stack
  final double rowGap;
  final double stackGap;

  /// space before the suffix
  final double suffixGap;

  @override
  State<MorphLayout> createState() => _MorphLayoutState();
}

class _MorphLayoutState extends State<MorphLayout>
    with SingleTickerProviderStateMixin {
  // 0 = one line, 1 = stacked
  late final AnimationController _c = AnimationController.unbounded(
    vsync: this,
    value: widget.stacked ? 1 : 0,
  );

  @override
  void didUpdateWidget(MorphLayout old) {
    super.didUpdateWidget(old);
    if (old.stacked == widget.stacked) return;
    final target = widget.stacked ? 1.0 : 0.0;
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = target;
      return;
    }
    _c.animateWith(
      SpringSimulation(
        appleSpring(damping: 0.92, response: 0.55),
        _c.value,
        target,
        _c.velocity,
      ),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value.clamp(0.0, 1.0);
        return _MorphWidget(
          t: t,
          rowGap: widget.rowGap,
          stackGap: widget.stackGap,
          suffixGap: widget.suffixGap,
          children: [
            widget.hours,
            Opacity(
              opacity: 1 - t,
              child: widget.separator ?? const SizedBox.shrink(),
            ),
            widget.minutes,
            widget.trailing ?? const SizedBox.shrink(),
            widget.suffix ?? const SizedBox.shrink(),
          ],
        );
      },
    );
  }
}

class _MorphWidget extends MultiChildRenderObjectWidget {
  const _MorphWidget({
    required this.t,
    required this.rowGap,
    required this.stackGap,
    required this.suffixGap,
    required super.children,
  });

  final double t;
  final double rowGap;
  final double stackGap;
  final double suffixGap;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMorph(t, rowGap, stackGap, suffixGap);

  @override
  void updateRenderObject(BuildContext context, _RenderMorph render) {
    render
      ..t = t
      ..rowGap = rowGap
      ..stackGap = stackGap
      ..suffixGap = suffixGap;
  }
}

class _MorphData extends ContainerBoxParentData<RenderBox> {}

class _RenderMorph extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _MorphData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _MorphData> {
  _RenderMorph(this._t, this._rowGap, this._stackGap, this._suffixGap);

  double _t;
  double _rowGap;
  double _stackGap;
  double _suffixGap;

  set suffixGap(double v) {
    if (v == _suffixGap) return;
    _suffixGap = v;
    markNeedsLayout();
  }

  set t(double v) {
    if (v == _t) return;
    _t = v;
    markNeedsLayout();
  }

  set rowGap(double v) {
    if (v == _rowGap) return;
    _rowGap = v;
    markNeedsLayout();
  }

  set stackGap(double v) {
    if (v == _stackGap) return;
    _stackGap = v;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _MorphData) child.parentData = _MorphData();
  }

  List<RenderBox> get _kids {
    final out = <RenderBox>[];
    var c = firstChild;
    while (c != null) {
      out.add(c);
      c = childAfter(c);
    }
    return out;
  }

  // The two arrangements, for children of sizes [s] (hours, separator,
  // minutes, trailing): where each goes, and how big the whole is.
  ({List<Offset> at, Size size}) _row(List<Size> s) {
    final h = s[0], sep = s[1], m = s[2], tr = s[3], su = s[4];
    final gapsAfterHours = sep.width > 0 ? _rowGap : 0.0;
    final body =
        h.width +
        gapsAfterHours +
        sep.width +
        gapsAfterHours +
        m.width +
        (tr.width > 0 ? _rowGap + tr.width : 0);
    final width = body + (su.width > 0 ? _suffixGap + su.width : 0);
    final height = [
      h.height,
      sep.height,
      m.height,
      tr.height,
      su.height,
    ].reduce((a, b) => a > b ? a : b);
    var x = 0.0;
    final at = <Offset>[];
    at.add(Offset(x, (height - h.height) / 2));
    x += h.width + gapsAfterHours;
    at.add(Offset(x, (height - sep.height) / 2));
    x += sep.width + gapsAfterHours;
    at.add(Offset(x, (height - m.height) / 2));
    x += m.width + (tr.width > 0 ? _rowGap : 0);
    at.add(Offset(x, height - tr.height)); // along the bottom
    x += tr.width + _suffixGap;
    at.add(Offset(x, height - su.height)); // AM/PM at the baseline end
    return (at: at, size: Size(width, height));
  }

  ({List<Offset> at, Size size}) _stack(List<Size> s) {
    final h = s[0], m = s[2], tr = s[3], su = s[4];
    final block = [h.width, m.width, tr.width].reduce((a, b) => a > b ? a : b);
    var y = 0.0;
    final at = <Offset>[];
    at.add(Offset((block - h.width) / 2, y));
    y += h.height + _stackGap;
    at.add(Offset(block / 2, y)); // the colon: folded away, in the middle
    final minutesY = y;
    at.add(Offset((block - m.width) / 2, y));
    y += m.height;
    // the last line: seconds if there are any, else the minutes
    var lastX = (block - m.width) / 2 + m.width;
    var lastY = minutesY;
    var lastH = m.height;
    if (tr.height > 0) {
      y += _stackGap;
      at.add(Offset((block - tr.width) / 2, y));
      lastX = (block - tr.width) / 2 + tr.width;
      lastY = y;
      lastH = tr.height;
      y += tr.height;
    } else {
      at.add(Offset(block / 2, y));
    }
    // AM/PM hangs off the right end of the last line, at its bottom
    final sx = lastX + (su.width > 0 ? _suffixGap : 0);
    at.add(Offset(sx, lastY + lastH - su.height));
    final width = su.width > 0
        ? (sx + su.width > block ? sx + su.width : block)
        : block;
    return (at: at, size: Size(width, y));
  }

  List<Size> _sizes(List<RenderBox> kids, {required bool dry}) => [
    for (final k in kids) dry ? k.getDryLayout(const BoxConstraints()) : k.size,
  ];

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final s = _sizes(_kids, dry: true);
    final r = _row(s).size, c = _stack(s).size;
    return constraints.constrain(Size.lerp(r, c, _t)!);
  }

  @override
  void performLayout() {
    final kids = _kids;
    for (final k in kids) {
      k.layout(const BoxConstraints(), parentUsesSize: true);
    }
    final s = _sizes(kids, dry: false);
    final r = _row(s), c = _stack(s);
    final size = Size.lerp(r.size, c.size, _t)!;
    this.size = constraints.constrain(size);
    // each arrangement is centred in the (changing) box, then blended
    final fromRow = Offset(
      (size.width - r.size.width) / 2,
      (size.height - r.size.height) / 2,
    );
    final fromStack = Offset(
      (size.width - c.size.width) / 2,
      (size.height - c.size.height) / 2,
    );
    for (var i = 0; i < kids.length; i++) {
      (kids[i].parentData! as _MorphData).offset = Offset.lerp(
        r.at[i] + fromRow,
        c.at[i] + fromStack,
        _t,
      )!;
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
