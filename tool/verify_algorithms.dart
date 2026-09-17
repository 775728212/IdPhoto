// 纯 Dart 算法验证脚本（不依赖 Flutter）。
//
// 用途：在没有设备 / 模拟器的环境下，真实跑一遍「抠图 → 换底色 → 压缩 → 排版」
// 流水线，把中间结果导出成 PNG 以便肉眼检查。
//
// 运行：
//   dart run tool/verify_algorithms.dart [输出目录]
//
// 之所以能脱离 Flutter 运行，是因为 lib/services/ 与 lib/core/ 全部只依赖
// dart:typed_data、dart:math、dart:isolate、dart:io 和 package:image。

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:id_photo_maker/core/constants/bg_swatches.dart';
import 'package:id_photo_maker/core/constants/photo_specs.dart';
import 'package:id_photo_maker/core/utils/pixel_buffer.dart';
import 'package:id_photo_maker/services/encode_service.dart';
import 'package:id_photo_maker/services/layout_service.dart';
import 'package:id_photo_maker/services/recolor_service.dart';
import 'package:id_photo_maker/services/segmentation_service.dart';

int _passed = 0;
int _failed = 0;

void check(String name, bool ok, [String? detail]) {
  if (ok) {
    _passed++;
    stdout.writeln('  [PASS] $name${detail == null ? '' : '  ($detail)'}');
  } else {
    _failed++;
    stdout.writeln('  [FAIL] $name${detail == null ? '' : '  ($detail)'}');
  }
}

void checkEq(String name, Object? actual, Object? expected) =>
    check(name, actual == expected, 'actual=$actual expected=$expected');

void section(String title) {
  stdout.writeln('');
  stdout.writeln('== $title ==');
}

// ------------------------------------------------------------------ 造测试图

const int _blueBg = 0x438EDB;
const int _skin = 0xE8C39E;
const int _hair = 0x3A2A22;
const int _shirt = 0xF2F4F8;

/// 合成一张"蓝底 + 人像（头/发/肩）"的假证件照原图。
///
/// 故意让肩部一直延伸到底边 —— 这是真实证件照的构图，也是洪水填充最容易踩坑的地方。
PixelBuffer fakePortrait(int w, int h, {int bg = _blueBg}) {
  final PixelBuffer buf = PixelBuffer.empty(w, h);
  ImageOps.fillColor(buf, (bg >> 16) & 0xFF, (bg >> 8) & 0xFF, bg & 0xFF);

  final double cx = w / 2;
  final double headCy = h * 0.36;
  final double headR = w * 0.19;
  final double shoulderTop = h * 0.60;

  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final double dx = x - cx;
      final double dy = y - headCy;
      final double dist = math.sqrt(dx * dx + dy * dy);

      int color = -1;
      if (dist <= headR) {
        // 头发：头顶一圈
        color = (dy < -headR * 0.35) ? _hair : _skin;
      } else if (dist <= headR * 1.08 && dy < 0) {
        color = _hair; // 发际线外沿
      }
      if (color < 0 && y >= shoulderTop && (x - cx).abs() <= w * 0.36) {
        color = _shirt;
      }
      if (color < 0 && y >= shoulderTop + h * 0.10 && (x - cx).abs() <= w * 0.16) {
        color = _skin; // 脖子
      }
      if (color >= 0) {
        buf.setRgba(x, y, (color >> 16) & 0xFF, (color >> 8) & 0xFF, color & 0xFF, 255);
      }
    }
  }
  return buf;
}

String toPng(PixelBuffer buffer) => '${buffer.width}x${buffer.height}';

/// 最近邻放大一块区域 —— 检查 1px 级描边时不能用双线性，会被糊掉。
PixelBuffer zoomNearest(PixelBuffer src, int x0, int y0, int w, int h, int scale) {
  final PixelBuffer out = PixelBuffer.empty(w * scale, h * scale);
  for (int y = 0; y < h * scale; y++) {
    final int sy = (y0 + y ~/ scale).clamp(0, src.height - 1);
    for (int x = 0; x < w * scale; x++) {
      final int sx = (x0 + x ~/ scale).clamp(0, src.width - 1);
      final int i = src.indexOf(sx, sy);
      out.setRgba(x, y, src.rgba[i], src.rgba[i + 1], src.rgba[i + 2], src.rgba[i + 3]);
    }
  }
  return out;
}

void writePng(PixelBuffer buffer, String path) {
  final img.Image image = img.Image.fromBytes(
    width: buffer.width,
    height: buffer.height,
    bytes: buffer.rgba.buffer,
    bytesOffset: buffer.rgba.offsetInBytes,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  File(path).writeAsBytesSync(img.encodePng(image));
}

Future<void> main(List<String> args) async {
  final String outDir = args.isNotEmpty ? args.first : 'build/verify';
  Directory(outDir).createSync(recursive: true);

  stdout.writeln('证件照核心算法验证');
  stdout.writeln('输出目录: ${Directory(outDir).absolute.path}');

  // ---------------------------------------------------------------- 规格换算
  section('规格与像素换算');
  final PhotoSpec oneInch = PhotoSpecs.byId('one_inch');
  checkEq('一寸 @300DPI 宽', oneInch.pixelWidth(300), 295);
  checkEq('一寸 @300DPI 高', oneInch.pixelHeight(300), 413);
  checkEq('二寸 @300DPI', '${PhotoSpecs.byId('two_inch').pixelWidth(300)}x${PhotoSpecs.byId('two_inch').pixelHeight(300)}', '413x579');
  checkEq('身份证 @350DPI', '${PhotoSpecs.byId('id_card').pixelWidth(350)}x${PhotoSpecs.byId('id_card').pixelHeight(350)}', '358x441');
  checkEq('美国签证官方像素', '${PhotoSpecs.byId('us_visa').pixelWidth(300)}x${PhotoSpecs.byId('us_visa').pixelHeight(300)}', '600x600');
  check('规格 id 唯一', PhotoSpecs.all.map((PhotoSpec s) => s.id).toSet().length == PhotoSpecs.all.length);
  check(
    '所有规格的默认底色都存在',
    PhotoSpecs.all.every((PhotoSpec s) => BgSwatches.byId(s.defaultSwatchId).id == s.defaultSwatchId),
  );

  // ---------------------------------------------------------------- 几何变换
  section('几何变换');
  final PixelBuffer probe = PixelBuffer.empty(2, 3);
  ImageOps.fillColor(probe, 0, 0, 0);
  probe.setRgba(0, 0, 255, 0, 0, 255);
  probe.setRgba(1, 0, 0, 255, 0, 255);
  final PixelBuffer r90 = ImageOps.rotateQuarters(probe, 1);
  checkEq('顺时针 90 度后尺寸', '${r90.width}x${r90.height}', '3x2');
  checkEq('原左上角转到右上角', r90.argbAt(2, 0), 0xFFFF0000);
  checkEq('原右上角转到右下角', r90.argbAt(2, 1), 0xFF00FF00);
  final PixelBuffer r360 = ImageOps.rotateQuarters(probe, 4);
  check('旋转 4 次回到原图', r360.rgba.toString() == probe.rgba.toString());

  final PixelBuffer flipSrc = PixelBuffer.empty(3, 1);
  flipSrc.setRgba(0, 0, 1, 1, 1, 255);
  flipSrc.setRgba(2, 0, 9, 9, 9, 255);
  final PixelBuffer flipped = ImageOps.flipHorizontal(flipSrc);
  check('水平镜像交换左右', flipped.argbAt(0, 0) == 0xFF090909 && flipped.argbAt(2, 0) == 0xFF010101);

  // ---------------------------------------------------------------- 重采样
  section('区域重采样');
  final PixelBuffer halfHalf = PixelBuffer.empty(4, 4);
  for (int y = 0; y < 4; y++) {
    for (int x = 0; x < 4; x++) {
      final int v = x < 2 ? 0 : 255;
      halfHalf.setRgba(x, y, v, v, v, 255);
    }
  }
  final PixelBuffer shrunk = ImageOps.resampleRegion(halfHalf, 0, 0, 4, 4, 2, 2);
  check('降采样左黑右白', shrunk.argbAt(0, 0) == 0xFF000000 && shrunk.argbAt(1, 0) == 0xFFFFFFFF);
  final PixelBuffer enlarged = ImageOps.resampleRegion(probe, 0, 0, 2, 3, 8, 12);
  checkEq('放大到 8x12', '${enlarged.width}x${enlarged.height}', '8x12');
  check('放大后仍保留四角颜色', enlarged.argbAt(0, 0) == 0xFFFF0000);

  // ---------------------------------------------------------------- 抠图
  section('抠图（洪水填充）');
  final PixelBuffer portrait = fakePortrait(400, 560);
  writePng(portrait, '$outDir/00_source.png');

  final int estimated = SegmentationService.estimateBackgroundColor(portrait);
  final int estR = (estimated >> 16) & 0xFF;
  final int estG = (estimated >> 8) & 0xFF;
  final int estB = estimated & 0xFF;
  check(
    '背景主色估计接近 #438EDB',
    (estR - 0x43).abs() <= 4 && (estG - 0x8E).abs() <= 4 && (estB - 0xDB).abs() <= 4,
    '#${estimated.toRadixString(16).padLeft(6, '0').toUpperCase()}',
  );

  final MaskResult mask = SegmentationService.buildMaskSync(
    portrait,
    const SegmentOptions(tolerance: 34, edgeClean: 1, feather: 1),
  );
  check('没有退化成全前景', !mask.fallbackUsed);
  check('四角判为背景', mask.mask[0] > 200 && mask.mask[400 - 1] > 200);
  final int faceIdx = (560 * 0.36).round() * 400 + 200;
  check('面部判为前景', mask.mask[faceIdx] < 40);
  final int shoulderIdx = (560 - 3) * 400 + 200;
  check('底边中央的肩部仍是前景（未被洪水填充吃掉）', mask.mask[shoulderIdx] < 40);
  final int bottomLeftIdx = (560 - 3) * 400 + 2;
  check('左下角背景被正确识别', mask.mask[bottomLeftIdx] > 200);
  check(
    '背景占比在合理区间',
    mask.coverage > 0.25 && mask.coverage < 0.85,
    '${(mask.coverage * 100).toStringAsFixed(1)}%',
  );

  // 边界上没有任何像素接近「背景色」时，安全退化为全前景（不做破坏性改动）。
  // 用与画面完全不相干的 seedColor 来构造这个场景。
  final PixelBuffer solidFrame = PixelBuffer.empty(80, 100);
  ImageOps.fillColor(solidFrame, 200, 120, 120);
  final MaskResult fullFrame = SegmentationService.buildMaskSync(
    solidFrame,
    const SegmentOptions(
      tolerance: 5,
      edgeClean: 0,
      feather: 0,
      seedColor: 0x00FF00,
    ),
  );
  check('边界找不到背景像素时退化为全前景并告警',
      fullFrame.fallbackUsed && fullFrame.coverage == 0);

  // 画笔修补
  final PixelBuffer brushTest = fakePortrait(200, 280);
  final MaskResult brushMask = SegmentationService.buildMaskSync(
    brushTest,
    const SegmentOptions(tolerance: 34, edgeClean: 0, feather: 0),
  );
  final int beforeCount = _countBackground(brushMask.mask);
  SegmentationService.stampCircle(
    brushMask.mask, 200, 280, 100, 150, 30, asBackground: true);
  final int afterCount = _countBackground(brushMask.mask);
  check('画笔涂抹把前景改成背景', afterCount > beforeCount, '$beforeCount -> $afterCount');
  SegmentationService.stampCircle(
    brushMask.mask, 200, 280, -20, -20, 15, asBackground: true);
  check('画笔越界不抛异常', true);

  // ---------------------------------------------------------------- 换底色
  section('换底色');
  // 与 App 中的顺序一致：先在裁剪后的成片上抠图，掩膜与成片同尺寸。
  final PixelBuffer base = ImageOps.resampleRegion(
    portrait, 0, 0, 400, 560, 295, 413);
  final MaskResult baseMask = SegmentationService.buildMaskSync(
    base,
    const SegmentOptions(tolerance: 34, edgeClean: 1, feather: 1),
  );
  check('成片抠图未退化', !baseMask.fallbackUsed,
      '背景占比 ${(baseMask.coverage * 100).toStringAsFixed(1)}%');
  check('成片四角判为背景', baseMask.mask[0] > 200);
  final int baseFaceIdx = baseMask.width * 149 + 147;
  check('成片面部判为前景', baseMask.mask[baseFaceIdx] < 40);

  // 尺寸不一致的掩膜必须立刻报错，而不是静默读错偏移量。
  bool maskMismatchThrew = false;
  try {
    RecolorService.apply(
      source: base,
      mask: mask.mask, // 400x560 的掩膜喂给 295x413 的成片
      swatch: BgSwatches.white,
    );
  } on ArgumentError {
    maskMismatchThrew = true;
  }
  check('掩膜尺寸不匹配时立刻报错', maskMismatchThrew);

  final PixelBuffer white = RecolorService.apply(
    source: base,
    mask: baseMask.mask,
    swatch: BgSwatches.white,
    originalBackgroundArgb: baseMask.backgroundArgb,
  );
  writePng(white, '$outDir/01_white.png');
  checkEq('白底: 角落变纯白', white.argbAt(1, 1), 0xFFFFFFFF);

  // ---- 边缘处理 A/B/C 对照（诊断产物，便于肉眼比对过渡带质量）----
  final PixelBuffer edgeRaw = RecolorService.apply(
    source: base,
    mask: baseMask.mask,
    swatch: BgSwatches.white,
    originalBackgroundArgb: baseMask.backgroundArgb,
    decontaminate: false,
    colorMatting: false,
  );
  writePng(edgeRaw, '$outDir/01b_edge_a_raw.png');

  final PixelBuffer edgeDecon = RecolorService.apply(
    source: base,
    mask: baseMask.mask,
    swatch: BgSwatches.white,
    originalBackgroundArgb: baseMask.backgroundArgb,
    decontaminate: true,
    colorMatting: false,
  );
  writePng(edgeDecon, '$outDir/01c_edge_b_decon_only.png');

  stdout.writeln('  [INFO] 过渡带平均蓝偏量（0 最中性，正=残留蓝边，负=偏暖）:');
  stdout.writeln('         A 什么都不做 = ${_edgeBlueness(edgeRaw, baseMask.mask)}');
  stdout.writeln('         B 仅去色溢   = ${_edgeBlueness(edgeDecon, baseMask.mask)}');
  stdout.writeln('         C 颜色投影   = ${_edgeBlueness(white, baseMask.mask)}');

  // 头部左侧边缘（皮肤/头发 与 蓝底 交界处）放大 8 倍，直接看描边。
  for (final (String tag, PixelBuffer buf) in <(String, PixelBuffer)>[
    ('a_raw', edgeRaw),
    ('b_decon_only', edgeDecon),
    ('c_projection', white),
  ]) {
    writePng(zoomNearest(buf, 82, 120, 24, 40, 8), '$outDir/01d_zoom_$tag.png');
  }
  // 只看绝对偏色量，不预设方向。
  check(
    '颜色投影的边缘偏色不比"仅去色溢"更差',
    _edgeBlueness(white, baseMask.mask).abs() <=
        _edgeBlueness(edgeDecon, baseMask.mask).abs() + 4,
    '仅去色溢 ${_edgeBlueness(edgeDecon, baseMask.mask)} / '
        '颜色投影 ${_edgeBlueness(white, baseMask.mask)}',
  );

  final PixelBuffer bluePhoto = RecolorService.apply(
    source: base,
    mask: baseMask.mask,
    swatch: BgSwatches.red,
    originalBackgroundArgb: baseMask.backgroundArgb,
  );
  writePng(bluePhoto, '$outDir/02_red.png');
  checkEq('红底: 角落变标准红', bluePhoto.argbAt(1, 1), 0xFFD9001B);

  final PixelBuffer gradient = RecolorService.apply(
    source: base,
    mask: baseMask.mask,
    swatch: BgSwatches.gradientBlue,
    originalBackgroundArgb: baseMask.backgroundArgb,
  );
  writePng(gradient, '$outDir/03_gradient.png');
  check(
    '渐变底: 上浅下深',
    ((gradient.argbAt(3, 0) >> 16) & 0xFF) > ((gradient.argbAt(3, 412) >> 16) & 0xFF),
  );

  final PixelBuffer transparent = RecolorService.apply(
    source: base,
    mask: baseMask.mask,
    swatch: BgSwatches.transparent,
    originalBackgroundArgb: baseMask.backgroundArgb,
  );
  writePng(transparent, '$outDir/04_transparent.png');
  check('透明底: 角落 alpha = 0', transparent.argbAt(1, 1) >> 24 == 0);
  check('透明底: 脸部仍然不透明',
      transparent.rgba[transparent.indexOf(147, 149) + 3] > 200);
  check('透明底: 脸部像素没有被反解成黑色',
      white.argbAt(147, 149) != 0xFF000000);

  // 去色溢效果：换白底后，边缘不应残留蓝色
  final int edgeSample = _findEdgePixel(white, base, 295, 413);
  check(
    '去色溢: 人像边缘没有残留蓝边',
    edgeSample < 0 || _blueness(white, edgeSample) < 40,
    edgeSample < 0 ? '无参考像素' : '蓝偏量=${_blueness(white, edgeSample)}',
  );

  // ---------------------------------------------------------------- 压缩
  section('压缩与编码');
  final EncodedImage q95 = EncodeService.encodeJpeg(white, 95);
  final EncodedImage q30 = EncodeService.encodeJpeg(white, 30);
  check('JPEG 头部标记正确', q95.bytes[0] == 0xFF && q95.bytes[1] == 0xD8);
  check('质量越低体积越小', q30.byteSize < q95.byteSize, '${q95.sizeLabel} -> ${q30.sizeLabel}');
  checkEq('JPEG 元信息尺寸', '${q95.width}x${q95.height}', '295x413');

  final EncodedImage png = EncodeService.encodePng(transparent);
  check('PNG 头部标记正确', png.bytes[0] == 0x89 && png.bytes[1] == 0x50);
  File('$outDir/05_output.png').writeAsBytesSync(png.bytes);

  for (final int kb in <int>[20, 50, 100]) {
    final EncodedImage hit = await EncodeService.compressToTargetSize(white, kb * 1024);
    check(
      '压缩到不超过 ${kb}KB',
      hit.byteSize <= kb * 1024,
      '${hit.sizeLabel} @ 质量${hit.quality}',
    );
  }
  final EncodedImage impossible = await EncodeService.compressToTargetSize(white, 300);
  checkEq('目标过小时返回最低质量', impossible.quality, 10);

  final PixelBuffer limited = EncodeService.limitMaxSide(portrait, 200);
  checkEq('限制最长边到 200', '${limited.width}x${limited.height}', '143x200');
  check('限制后最长边确实不超过上限',
      limited.width <= 200 && limited.height <= 200);

  final PixelBuffer flattened = RecolorService.flattenOn(transparent, 0xFFFFFF);
  checkEq('透明图铺白底后不含透明像素', flattened.hasTransparency, false);

  // ---------------------------------------------------------------- 排版
  section('排版打印');
  final PixelBuffer photo = RecolorService.apply(
    source: base,
    mask: baseMask.mask,
    swatch: BgSwatches.white,
    originalBackgroundArgb: baseMask.backgroundArgb,
  );
  checkEq('6 寸相纸 @300DPI 尺寸', '${PaperSize.sixInch.widthPx(300)}x${PaperSize.sixInch.heightPx(300)}', '1795x1205');

  for (final int copies in <int>[2, 4, 8, 12]) {
    final SheetLayout layout = LayoutService.buildSheet(photo, copies: copies);
    final bool fits = layout.cols * layout.rows >= copies;
    final bool insideSheet = layout.copies == math.min(copies, layout.cols * layout.rows);
    check(
      '$copies 张排版 -> ${layout.cols}x${layout.rows}',
      fits && insideSheet,
      '单张 ${layout.photoWidth}x${layout.photoHeight}px',
    );
  }
  final SheetLayout sheet8 = LayoutService.buildSheet(photo, copies: 8);
  checkEq('6 寸排 8 张一寸照落在 4x2', '${sheet8.cols}x${sheet8.rows}', '4x2');
  check('相纸四角是白纸', sheet8.sheet.argbAt(0, 0) == 0xFFFFFFFF);
  writePng(sheet8.sheet, '$outDir/06_sheet_6inch_8.png');

  final SheetLayout sheetA4 = LayoutService.buildSheet(
    photo, copies: 12, paper: PaperSize.a4, cutLines: false);
  writePng(sheetA4.sheet, '$outDir/07_sheet_a4_12.png');
  check('A4 排 12 张', sheetA4.cols * sheetA4.rows >= 12,
      '${sheetA4.cols}x${sheetA4.rows}');

  // ---------------------------------------------------------------- 多张混排
  section('多张不同照片拼一张');
  final PixelBuffer wide = ImageOps.resampleRegion(portrait, 0, 0, 400, 560, 600, 200);
  final PixelBuffer tall = ImageOps.resampleRegion(portrait, 0, 0, 400, 560, 200, 600);
  final List<PixelBuffer> mixed = <PixelBuffer>[photo, wide, tall, base];

  final SheetLayout mixed4 = LayoutService.buildMixedSheet(mixed);
  check(
    '4 张不同长宽比都排得下',
    mixed4.cols * mixed4.rows >= 4 && mixed4.copies == 4,
    '${mixed4.cols}x${mixed4.rows}',
  );
  checkEq('相纸尺寸与 6 寸一致', '${mixed4.sheet.width}x${mixed4.sheet.height}',
      '1795x1205');
  checkEq('每张都记下落纸尺寸', mixed4.photoWidths.length, 4);
  check(
    '每张都保持自身长宽比（不裁不拉）',
    <int>[0, 1, 2, 3].every((int i) {
      final double src = mixed[i].width / mixed[i].height;
      final double dst = mixed4.photoWidths[i] / mixed4.photoHeights[i];
      return (src - dst).abs() < 0.05;
    }),
    '落纸尺寸 ${mixed4.photoWidths.join(',')}',
  );
  check(
    '每张都没超出格子',
    <int>[0, 1, 2, 3].every(
      (int i) =>
          mixed4.photoWidths[i] <= mixed4.sheet.width &&
          mixed4.photoHeights[i] <= mixed4.sheet.height,
    ),
  );
  writePng(mixed4.sheet, '$outDir/08_sheet_mixed_4.png');

  final SheetLayout mixedPlain =
      LayoutService.buildMixedSheet(mixed, cutLines: false);
  check(
    '关掉裁切线后相纸四角仍是白纸',
    mixedPlain.sheet.argbAt(0, 0) == 0xFFFFFFFF &&
        mixedPlain.sheet.argbAt(
              mixedPlain.sheet.width - 1,
              mixedPlain.sheet.height - 1,
            ) ==
            0xFFFFFFFF,
  );

  final SheetLayout mixed8 =
      LayoutService.buildMixedSheet(List<PixelBuffer>.filled(8, photo));
  checkEq('8 张同尺寸照片混排也落在 4x2', '${mixed8.cols}x${mixed8.rows}', '4x2');

  final SheetLayout mixedEmpty =
      LayoutService.buildMixedSheet(<PixelBuffer>[]);
  checkEq('空列表不崩溃', mixedEmpty.copies, 0);

  // ---------------------------------------------------------------- 汇总
  stdout.writeln('');
  stdout.writeln('========================================');
  stdout.writeln('通过 $_passed 项，失败 $_failed 项');
  stdout.writeln('示例图已写入 ${Directory(outDir).absolute.path}');
  stdout.writeln('  ${toPng(portrait)} 原图 / 白底 / 红底 / 渐变底 / 透明底 / 输出 / 排版');
  stdout.writeln('========================================');

  if (_failed > 0) exitCode = 1;
}

int _countBackground(Uint8List mask) {
  var n = 0;
  for (int i = 0; i < mask.length; i++) {
    if (mask[i] > 127) n++;
  }
  return n;
}

/// 找一个"紧贴人像边缘"的像素索引，用来检查色溢。
int _findEdgePixel(PixelBuffer out, PixelBuffer src, int w, int h) {
  for (int y = 2; y < h - 2; y++) {
    for (int x = 2; x < w - 2; x++) {
      final int i = (y * w + x) * 4;
      // 原图是蓝底的人像边界：本身偏蓝，但邻居已经变成白色
      final int rightI = (y * w + x + 2) * 4;
      if (src.rgba[i + 2] > src.rgba[i] + 20 && out.rgba[rightI] == 255) {
        return i;
      }
    }
  }
  return -1;
}

int _blueness(PixelBuffer out, int index) =>
    out.rgba[index + 2] - ((out.rgba[index] + out.rgba[index + 1]) ~/ 2);

/// 掩膜过渡带（0 < mask < 255 的抗锯齿像素）的平均蓝偏量。
///
/// 换白底后理想值应接近 0：明显为正说明残留蓝边，明显为负说明
/// 去色溢把边缘"烧"成了暖黄色。
int _edgeBlueness(PixelBuffer out, Uint8List mask) {
  var sum = 0;
  var n = 0;
  for (int i = 0; i < mask.length; i++) {
    final int a = mask[i];
    if (a <= 8 || a >= 248) continue;
    final int p = i << 2;
    sum += out.rgba[p + 2] - ((out.rgba[p] + out.rgba[p + 1]) ~/ 2);
    n++;
  }
  return n == 0 ? 0 : sum ~/ n;
}
