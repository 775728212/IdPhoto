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
    required this.photoWidth,
    required this.photoHeight,
  });

  final PixelBuffer sheet;
  final String sheetName;
  final int cols;
  final int rows;
  final int copies;
  final int photoWidth;
  final int photoHeight;

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
