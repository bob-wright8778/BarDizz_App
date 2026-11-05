/// An axis-aligned rectangle in normalized frame coordinates (0..1 on both
/// axes, origin top-left), so it survives camera resolution changes.
class NormRect {
  const NormRect(this.left, this.top, this.right, this.bottom)
      : assert(left <= right && top <= bottom);

  /// Inputs: two opposite corners in any order.
  /// Outputs: the rectangle spanning them, clamped to the unit square.
  factory NormRect.fromCorners(double x1, double y1, double x2, double y2) {
    double c(double v) => v.clamp(0.0, 1.0);
    return NormRect(
      c(x1 < x2 ? x1 : x2),
      c(y1 < y2 ? y1 : y2),
      c(x1 < x2 ? x2 : x1),
      c(y1 < y2 ? y2 : y1),
    );
  }

  factory NormRect.fromJson(Map<String, dynamic> json) => NormRect(
        (json['l'] as num).toDouble(),
        (json['t'] as num).toDouble(),
        (json['r'] as num).toDouble(),
        (json['b'] as num).toDouble(),
      );

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;

  bool contains(double x, double y) => x >= left && x <= right && y >= top && y <= bottom;

  /// Outputs: this rectangle grown by [dx]/[dy] on every side, clamped to
  /// the unit square.
  NormRect inflate(double dx, double dy) =>
      NormRect.fromCorners(left - dx, top - dy, right + dx, bottom + dy);

  Map<String, dynamic> toJson() => {'l': left, 't': top, 'r': right, 'b': bottom};

  @override
  bool operator ==(Object other) =>
      other is NormRect &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);
}
