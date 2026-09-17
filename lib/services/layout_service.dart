import 'dart:math' as math;

import '../core/utils/pixel_buffer.dart';

/// 一张相纸上排好版的照片。
class SheetLayout {
  const SheetLayout({
    required this.sheet,
    required this.sheetName,
    required this.cols,
    required this.rows,
    required this.copies,
    this.photoWidth = 0,
    this.photoHeight = 0,
    this.photoWidths = const <int>[],
    this.photoHeights = const <int>[],
  });

  final PixelBuffer sheet;
  final String sheetName;
  final int cols;
  final int rows;
  final int copies;

  /// 「同一张照片印多份」时单张的输出尺寸。
  final int photoWidth;
  final int photoHeight;

  /// 「多张不同照片拼一张」时每张的实际落纸尺寸（顺序与输入一致）。
  /// 单张多份模式下为空。
  final List<int> photoWidths;
  final List<int> photoHeights;

  String get gridLabel => '$cols × $rows，共 $copies 张';
}

/// 常见相纸规格（毫米）。
class PaperSize {
  const PaperSize({required this.name, required this.widthMm, required this.heightMm});

  final String name;
  final double widthMm;
  final double heightMm;

  int widthPx(int dpi) => (widthMm / 25.4 * dpi).round();
  int heightPx(int dpi) => (heightMm / 25.4 * dpi).round();

  static const PaperSize sixInch =
      PaperSize(name: '6寸相纸', widthMm: 152, heightMm: 102);
  static const PaperSize fiveInch =
      PaperSize(name: '5寸相纸', widthMm: 127, heightMm: 89);
  static const PaperSize a4 = PaperSize(name: 'A4 相纸', widthMm: 210, heightMm: 297);

  /// A4 横放。证件照排版几乎总是横排更省纸，竖版 A4 反而会左右留大白边。
  static const PaperSize a4Landscape =
      PaperSize(name: 'A4 横版', widthMm: 297, heightMm: 210);

  /// 排版工具里提供给用户的相纸选项。
  static const List<PaperSize> presets = <PaperSize>[
    sixInch,
    fiveInch,
    a4Landscape,
  ];
}

/// 排版打印：把同一张证件照在一张相纸上多份排开，方便一次冲印。
///
/// 自动在所有 (列 × 行) 组合中挑选**照片缩放比例最大**的一种，
/// 保证尽量占满相纸、减少白边。
class LayoutService {
  LayoutService._();

  static SheetLayout buildSheet(
    PixelBuffer photo, {
    required int copies,
    PaperSize paper = PaperSize.sixInch,
    int dpi = 300,
    int gap = 8,
    bool cutLines = true,
    int backgroundArgb = 0xFFFFFF,
  }) {
    final int sheetW = paper.widthPx(dpi);
    final int sheetH = paper.heightPx(dpi);

    double bestScale = 0;
    int bestCols = 1;
    int bestRows = 1;

    for (int cols = 1; cols <= copies; cols++) {
      final int rows = (copies / cols).ceil();
      final double cellW = (sheetW - (cols - 1) * gap) / cols;
      final double cellH = (sheetH - (rows - 1) * gap) / rows;
      if (cellW <= 0 || cellH <= 0) continue;
      final double scale = math.min(cellW / photo.width, cellH / photo.height);
      if (scale > bestScale) {
        bestScale = scale;
        bestCols = cols;
        bestRows = rows;
      }
    }

    if (bestScale <= 0) {
      bestScale = 1;
      bestCols = 1;
      bestRows = 1;
    }

    final int cellW = (sheetW - (bestCols - 1) * gap) ~/ bestCols;
    final int cellH = (sheetH - (bestRows - 1) * gap) ~/ bestRows;
    final int pw = math.max(1, (photo.width * bestScale).round());
    final int ph = math.max(1, (photo.height * bestScale).round());

    final PixelBuffer sheet = PixelBuffer.empty(sheetW, sheetH);
    ImageOps.fillColor(
      sheet,
      (backgroundArgb >> 16) & 0xFF,
      (backgroundArgb >> 8) & 0xFF,
      backgroundArgb & 0xFF,
    );

    final PixelBuffer scaled = ImageOps.resampleRegion(
      photo,
      0,
      0,
      photo.width.toDouble(),
      photo.height.toDouble(),
      pw,
      ph,
    );

    final int contentW = bestCols * cellW + (bestCols - 1) * gap;
    final int contentH = bestRows * cellH + (bestRows - 1) * gap;
    final int originX = ((sheetW - contentW) / 2).round();
    final int originY = ((sheetH - contentH) / 2).round();

    for (int i = 0; i < copies; i++) {
      final int col = i % bestCols;
      final int row = i ~/ bestCols;
      if (row >= bestRows) break;

      final int cellX = originX + col * (cellW + gap);
      final int cellY = originY + row * (cellH + gap);
      // 每格内居中
      final int dx = cellX + (cellW - pw) ~/ 2;
      final int dy = cellY + (cellH - ph) ~/ 2;
      ImageOps.blit(sheet, scaled, dx, dy);

      if (cutLines) {
        _strokeRect(sheet, dx - 1, dy - 1, pw + 2, ph + 2, 0xC0C4CC);
      }
    }

    return SheetLayout(
      sheet: sheet,
      sheetName: paper.name,
      cols: bestCols,
      rows: bestRows,
      copies: math.min(copies, bestCols * bestRows),
      photoWidth: pw,
      photoHeight: ph,
    );
  }

  /// 把**多张互不相同**的照片拼到一张相纸上。
  ///
  /// 与 [buildSheet] 的区别：这里的每张照片长宽比可以完全不同，所以不能在
  /// 外面先确定一个「单张尺寸」再复制。做法是：
  ///  1. 枚举所有 (列 × 行) 组合，把每张照片各自等比缩放到格子里，
  ///     累计「实际落纸面积」，取面积最大的那个组合；
  ///  2. 逐格居中贴图，每张保持自己的比例，不裁切、不拉伸。
  ///
  /// 不做裁切是刻意的 —— 拼图工具已经让用户逐张裁剪过了，这里再裁一次
  /// 等于推翻用户的选择。
  static SheetLayout buildMixedSheet(
    List<PixelBuffer> photos, {
    PaperSize paper = PaperSize.sixInch,
    int dpi = 300,
    int gap = 8,
    bool cutLines = true,
    int backgroundArgb = 0xFFFFFF,
  }) {
    final int sheetW = paper.widthPx(dpi);
    final int sheetH = paper.heightPx(dpi);

    final PixelBuffer sheet = PixelBuffer.empty(sheetW, sheetH);
    ImageOps.fillColor(
      sheet,
      (backgroundArgb >> 16) & 0xFF,
      (backgroundArgb >> 8) & 0xFF,
      backgroundArgb & 0xFF,
    );

    final int n = photos.length;
    if (n == 0) {
      return SheetLayout(
        sheet: sheet,
        sheetName: paper.name,
        cols: 0,
        rows: 0,
        copies: 0,
      );
    }

    int bestCols = 1;
    int bestRows = n;
    double bestArea = -1;

    for (int cols = 1; cols <= n; cols++) {
      final int rows = (n / cols).ceil();
      final double cellW = (sheetW - (cols - 1) * gap) / cols;
      final double cellH = (sheetH - (rows - 1) * gap) / rows;
      if (cellW <= 0 || cellH <= 0) continue;

      double area = 0;
      for (final PixelBuffer photo in photos) {
        final double scale = math.min(cellW / photo.width, cellH / photo.height);
        if (scale <= 0) continue;
        area += (photo.width * scale) * (photo.height * scale);
      }
      if (area > bestArea) {
        bestArea = area;
        bestCols = cols;
        bestRows = rows;
      }
    }

    final int cellW =
        math.max(1, (sheetW - (bestCols - 1) * gap) ~/ bestCols);
    final int cellH =
        math.max(1, (sheetH - (bestRows - 1) * gap) ~/ bestRows);

    final int contentW = bestCols * cellW + (bestCols - 1) * gap;
    final int contentH = bestRows * cellH + (bestRows - 1) * gap;
    final int originX = ((sheetW - contentW) / 2).round();
    final int originY = ((sheetH - contentH) / 2).round();

    final List<int> widths = <int>[];
    final List<int> heights = <int>[];

    for (int i = 0; i < n; i++) {
      final int col = i % bestCols;
      final int row = i ~/ bestCols;
      if (row >= bestRows) break;

      final PixelBuffer photo = photos[i];
      final double scale = math.min(
        cellW / photo.width,
        cellH / photo.height,
      );
      final int pw = math.max(1, (photo.width * scale).round()).clamp(1, cellW);
      final int ph = math.max(1, (photo.height * scale).round()).clamp(1, cellH);

      final int cellX = originX + col * (cellW + gap);
      final int cellY = originY + row * (cellH + gap);
      final int dx = cellX + (cellW - pw) ~/ 2;
      final int dy = cellY + (cellH - ph) ~/ 2;

      if (pw == photo.width && ph == photo.height) {
        ImageOps.blit(sheet, photo, dx, dy);
      } else {
        final PixelBuffer scaled = ImageOps.resampleRegion(
          photo,
          0,
          0,
          photo.width.toDouble(),
          photo.height.toDouble(),
          pw,
          ph,
        );
        ImageOps.blit(sheet, scaled, dx, dy);
      }

      if (cutLines) {
        _strokeRect(sheet, dx - 1, dy - 1, pw + 2, ph + 2, 0xC0C4CC);
      }

      widths.add(pw);
      heights.add(ph);
    }

    return SheetLayout(
      sheet: sheet,
      sheetName: paper.name,
      cols: bestCols,
      rows: bestRows,
      copies: math.min(n, bestCols * bestRows),
      photoWidths: widths,
      photoHeights: heights,
    );
  }

  static void _strokeRect(PixelBuffer target, int x, int y, int w, int h, int argb) {
    final int r = (argb >> 16) & 0xFF;
    final int g = (argb >> 8) & 0xFF;
    final int b = argb & 0xFF;
    final int x1 = x + w - 1;
    final int y1 = y + h - 1;

    for (int i = x; i <= x1; i++) {
      _put(target, i, y, r, g, b);
      _put(target, i, y1, r, g, b);
    }
    for (int j = y; j <= y1; j++) {
      _put(target, x, j, r, g, b);
      _put(target, x1, j, r, g, b);
    }
  }

  static void _put(PixelBuffer target, int x, int y, int r, int g, int b) {
    if (x < 0 || y < 0 || x >= target.width || y >= target.height) return;
    target.setRgba(x, y, r, g, b, 255);
  }
}
