import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:id_photo_maker/core/constants/bg_swatches.dart';
import 'package:id_photo_maker/core/constants/photo_specs.dart';
import 'package:id_photo_maker/core/utils/pixel_buffer.dart';
import 'package:id_photo_maker/services/encode_service.dart';
import 'package:id_photo_maker/services/layout_service.dart';
import 'package:id_photo_maker/services/recolor_service.dart';
import 'package:id_photo_maker/services/segmentation_service.dart';

const int blueBg = 0x438EDB;
const int beigeFg = 0xE8C39E;

/// 造一张"蓝底 + 中间偏下一个米色人像"的测试图。
PixelBuffer fakePortrait(int w, int h) {
  final PixelBuffer buf = PixelBuffer.empty(w, h);
  ImageOps.fillColor(
    buf,
    (blueBg >> 16) & 0xFF,
    (blueBg >> 8) & 0xFF,
    blueBg & 0xFF,
  );

  // 头部（圆形）
  final double cx = w / 2;
  final double cy = h * 0.38;
  final double headR = w * 0.20;
  // 肩部（矩形，一直延伸到下边界，模拟真实证件照构图）
  final double shoulderTop = h * 0.62;

  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final double dx = x - cx;
      final double dy = y - cy;
      final bool inHead = (dx * dx + dy * dy) <= headR * headR;
      final bool inShoulder = y >= shoulderTop && (x - cx).abs() <= w * 0.34;
      if (inHead || inShoulder) {
        buf.setRgba(
          x,
          y,
          (beigeFg >> 16) & 0xFF,
          (beigeFg >> 8) & 0xFF,
          beigeFg & 0xFF,
          255,
        );
      }
    }
  }
  return buf;
}

void main() {
  group('PhotoSpec 像素换算', () {
    test('一寸 300DPI 应为 295x413', () {
      final PhotoSpec s = PhotoSpecs.byId('one_inch');
      expect(s.pixelWidth(300), 295);
      expect(s.pixelHeight(300), 413);
      expect(s.aspectRatio, closeTo(25 / 35, 1e-9));
    });

    test('二寸 300DPI 应为 413x579', () {
      final PhotoSpec s = PhotoSpecs.byId('two_inch');
      expect(s.pixelWidth(300), 413);
      expect(s.pixelHeight(300), 579);
    });

    test('身份证 350DPI 应为 358x441', () {
      final PhotoSpec s = PhotoSpecs.byId('id_card');
      expect(s.pixelWidth(350), 358);
      expect(s.pixelHeight(350), 441);
    });

    test('美国签证使用官方像素覆盖值', () {
      final PhotoSpec s = PhotoSpecs.byId('us_visa');
      expect(s.pixelWidth(300), 600);
      expect(s.pixelHeight(300), 600);
    });

    test('规格 id 唯一且默认底色存在', () {
      final Set<String> ids = <String>{};
      for (final PhotoSpec s in PhotoSpecs.all) {
        expect(ids.add(s.id), isTrue, reason: '重复的规格 id: ${s.id}');
        expect(
          BgSwatches.byId(s.defaultSwatchId).id,
          s.defaultSwatchId,
          reason: '${s.name} 的默认底色 ${s.defaultSwatchId} 不存在',
        );
      }
    });

    test('自定义规格直接以像素为准，不被毫米舍入污染', () {
      final PhotoSpec custom =
          PhotoSpec.custom(widthPx: 300, heightPx: 400, dpi: 300);
      expect(custom.isCustom, isTrue);
      expect(custom.id, PhotoSpecs.customId);
      // 像素值是原样保留的，不会因为走了毫米换算而变成 299 或 401
      expect(custom.pixelWidth(300), 300);
      expect(custom.pixelHeight(300), 400);
      // 宽高比优先取像素，而不是由反算出的毫米值再除一遍
      expect(custom.aspectRatio, closeTo(300 / 400, 1e-9));
      // 换一个 dpi 也不该改变像素尺寸
      expect(custom.pixelWidth(600), 300);
      expect(custom.pixelHeight(600), 400);
    });

    test('自定义规格会夹紧到合法范围', () {
      final PhotoSpec tooSmall = PhotoSpec.custom(widthPx: 1, heightPx: 0);
      expect(tooSmall.pixelWidth(300), 16);
      expect(tooSmall.pixelHeight(300), 16);
    });

    test('自定义规格的毫米标签是干净的一位小数', () {
      // 300px @300DPI = 25.4mm，不该显示成 25.40mm
      final PhotoSpec custom = PhotoSpec.custom(widthPx: 300, heightPx: 413);
      expect(custom.mmLabel, '25.4×35mm');
    });
  });

  group('SegmentationService', () {
    test('自动识别出蓝色背景主色', () {
      final PixelBuffer portrait = fakePortrait(160, 220);
      final int bg = SegmentationService.estimateBackgroundColor(portrait);
      expect((bg >> 16) & 0xFF, closeTo(0x43, 2));
      expect((bg >> 8) & 0xFF, closeTo(0x8E, 2));
      expect(bg & 0xFF, closeTo(0xDB, 2));
    });

    test('掩膜把背景标为 255、人物标为 0', () {
      final PixelBuffer portrait = fakePortrait(160, 220);
      final MaskResult result = SegmentationService.buildMaskSync(
        portrait,
        const SegmentOptions(tolerance: 34, edgeClean: 1, feather: 1),
      );

      expect(result.fallbackUsed, isFalse);
      expect(result.width, 160);
      expect(result.height, 220);

      // 四角应为背景
      expect(result.mask[0], greaterThan(200));
      expect(result.mask[160 - 1], greaterThan(200));

      // 脸部中心应为前景
      final int faceIdx = (220 * 0.38).round() * 160 + 80;
      expect(result.mask[faceIdx], lessThan(40));

      // 肩部（底边中央）应仍是前景 —— 洪水填充不能从底边漏进人物里
      final int shoulderIdx = (220 - 2) * 160 + 80;
      expect(result.mask[shoulderIdx], lessThan(40));

      // 背景占比应该在合理区间
      expect(result.coverage, greaterThan(0.30));
      expect(result.coverage, lessThan(0.85));
    });

    test('容差为 0 时几乎抠不出背景', () {
      final PixelBuffer portrait = fakePortrait(120, 160);
      final MaskResult result = SegmentationService.buildMaskSync(
        portrait,
        const SegmentOptions(tolerance: 0, edgeClean: 0, feather: 0),
      );
      // 容差 0 只接受与主色完全一致的像素，背景主体仍会被识别（因为纯色）
      expect(result.coverage, greaterThan(0.2));
    });

    test('主体填满画面时退化为全前景', () {
      final PixelBuffer full = PixelBuffer.empty(80, 100);
      ImageOps.fillColor(full, 200, 120, 120);
      final MaskResult result = SegmentationService.buildMaskSync(
        full,
        const SegmentOptions(tolerance: 5, edgeClean: 0, feather: 0),
      );
      expect(result.fallbackUsed, isTrue);
      expect(result.coverage, 0.0);
    });

    test('指定 seedColor 可覆盖自动识别', () {
      final PixelBuffer portrait = fakePortrait(120, 160);
      final MaskResult result = SegmentationService.buildMaskSync(
        portrait,
        const SegmentOptions(tolerance: 30, seedColor: beigeFg, edgeClean: 0, feather: 0),
      );
      // 把人物颜色当成"背景色"，应该填满中心区域
      final int faceIdx = (160 * 0.38).round() * 120 + 60;
      expect(result.mask[faceIdx], greaterThan(200));
    });

    test('stampCircle / stampLine 能手动修补掩膜', () {
      final Uint8List mask = Uint8List(50 * 50);
      SegmentationService.stampCircle(mask, 50, 50, 10, 10, 4, asBackground: true);
      expect(mask[10 * 50 + 10], 255);
      expect(mask[10 * 50 + 30], 0);

      SegmentationService.stampLine(mask, 50, 50, 0, 40, 40, 40, 2, asBackground: true);
      expect(mask[40 * 50 + 0], 255);
      expect(mask[40 * 50 + 20], 255);
      expect(mask[40 * 50 + 40], 255);
    });

    test('stampCircle 越界不会抛异常', () {
      final Uint8List mask = Uint8List(20 * 20);
      expect(
        () => SegmentationService.stampCircle(mask, 20, 20, -5, -5, 8, asBackground: true),
        returnsNormally,
      );
      expect(
        () => SegmentationService.stampCircle(mask, 20, 20, 25, 25, 8, asBackground: false),
        returnsNormally,
      );
    });
  });

  group('RecolorService', () {
    test('纯背景像素被替换成目标底色', () {
      final PixelBuffer src = fakePortrait(100, 140);
      final MaskResult m = SegmentationService.buildMaskSync(
        src,
        const SegmentOptions(tolerance: 34, edgeClean: 1, feather: 1),
      );

      final PixelBuffer white = RecolorService.apply(
        source: src,
        mask: m.mask,
        swatch: BgSwatches.white,
        originalBackgroundArgb: m.backgroundArgb,
      );

      final int corner = white.argbAt(1, 1);
      expect(corner, 0xFFFFFFFF);

      // 脸部颜色应基本保持
      final int faceSrc = src.argbAt(50, 53);
      final int faceOut = white.argbAt(50, 53);
      expect((faceOut >> 16) & 0xFF, closeTo((faceSrc >> 16) & 0xFF, 6));
    });

    test('透明底色输出 alpha=0 的背景', () {
      final PixelBuffer src = fakePortrait(80, 110);
      final MaskResult m = SegmentationService.buildMaskSync(
        src,
        const SegmentOptions(tolerance: 34, edgeClean: 0, feather: 0),
      );
      final PixelBuffer out = RecolorService.apply(
        source: src,
        mask: m.mask,
        swatch: BgSwatches.transparent,
        originalBackgroundArgb: m.backgroundArgb,
      );
      expect(out.argbAt(0, 0) >> 24, 0);
      final int faceIdx = out.indexOf(40, 42);
      expect(out.rgba[faceIdx + 3], greaterThan(200));
    });

    test('渐变底色上下两端颜色不同', () {
      final PixelBuffer src = fakePortrait(80, 120);
      final Uint8List mask = Uint8List(80 * 120);
      for (int i = 0; i < mask.length; i++) {
        mask[i] = 255;
      }
      final PixelBuffer out = RecolorService.apply(
        source: src,
        mask: mask,
        swatch: BgSwatches.gradientBlue,
        originalBackgroundArgb: blueBg,
      );
      final int top = out.argbAt(40, 0);
      final int bottom = out.argbAt(40, 119);
      expect(top, isNot(equals(bottom)));
      // 渐变蓝：上浅下深
      expect((top >> 16) & 0xFF, greaterThan((bottom >> 16) & 0xFF));
    });

    test('flattenOn 把透明压到指定底色', () {
      final PixelBuffer src = PixelBuffer.empty(4, 4);
      ImageOps.fillColor(src, 10, 20, 30, 0);
      final PixelBuffer flat = RecolorService.flattenOn(src, 0xFFFFFF);
      expect(flat.argbAt(0, 0), 0xFFFFFFFF);
    });
  });

  group('EncodeService', () {
    test('JPEG 编码返回合法字节流与元信息', () {
      final PixelBuffer src = fakePortrait(295, 413);
      final EncodedImage e = EncodeService.encodeJpeg(src, 90);

      expect(e.extension, 'jpg');
      expect(e.mimeType, 'image/jpeg');
      expect(e.width, 295);
      expect(e.height, 413);
      expect(e.byteSize, greaterThan(1000));
      // JPEG SOI 标记
      expect(e.bytes[0], 0xFF);
      expect(e.bytes[1], 0xD8);
    });

    test('质量越低体积越小', () {
      final PixelBuffer src = fakePortrait(295, 413);
      final EncodedImage high = EncodeService.encodeJpeg(src, 95);
      final EncodedImage low = EncodeService.encodeJpeg(src, 30);
      expect(low.byteSize, lessThan(high.byteSize));
    });

    test('PNG 编码保留透明通道', () {
      final PixelBuffer src = fakePortrait(100, 140);
      final MaskResult m = SegmentationService.buildMaskSync(
        src,
        const SegmentOptions(tolerance: 34, edgeClean: 0, feather: 0),
      );
      final PixelBuffer cut = RecolorService.apply(
        source: src,
        mask: m.mask,
        swatch: BgSwatches.transparent,
        originalBackgroundArgb: m.backgroundArgb,
      );
      final EncodedImage e = EncodeService.encodePng(cut);
      expect(e.extension, 'png');
      expect(e.bytes[0], 0x89);
      expect(e.bytes[1], 0x50); // 'P'
    });

    test('encode(asPng:false) 遇到透明图会自动铺白底', () {
      final PixelBuffer src = PixelBuffer.empty(20, 20);
      ImageOps.fillColor(src, 10, 20, 30, 0);
      final EncodedImage e = EncodeService.encode(src, asPng: false);
      expect(e.extension, 'jpg');
      expect(e.byteSize, greaterThan(100));
    });

    test('compressToTargetSize 能卡到目标体积以内', () async {
      final PixelBuffer src = fakePortrait(413, 579);
      final int target = 30 * 1024;
      final EncodedImage e =
          await EncodeService.compressToTargetSize(src, target);
      expect(e.byteSize, lessThanOrEqualTo(target));
      expect(e.quality, greaterThanOrEqualTo(10));
    });

    test('目标体积过小时返回最低画质结果', () async {
      final PixelBuffer src = fakePortrait(413, 579);
      final EncodedImage e =
          await EncodeService.compressToTargetSize(src, 200);
      expect(e.quality, 10);
      expect(e.byteSize, greaterThan(0));
    });

    test('limitMaxSide 按最长边等比缩放', () {
      final PixelBuffer src = fakePortrait(1000, 500);
      final PixelBuffer out = EncodeService.limitMaxSide(src, 400);
      expect(out.width, 400);
      expect(out.height, 200);
    });

    test('limitMaxSide 不放大已足够小的图', () {
      final PixelBuffer src = fakePortrait(100, 200);
      final PixelBuffer out = EncodeService.limitMaxSide(src, 2400);
      expect(identical(out, src), isTrue);
    });

    test('formatBytes 输出可读文本', () {
      expect(formatBytes(512), '512 B');
      expect(formatBytes(2048), '2.0 KB');
      expect(formatBytes(3 * 1024 * 1024), '3.00 MB');
    });
  });

  group('LayoutService', () {
    test('6 寸相纸排 8 张一寸照应为 4x2', () {
      final PixelBuffer photo = fakePortrait(295, 413);
      final SheetLayout layout =
          LayoutService.buildSheet(photo, copies: 8, paper: PaperSize.sixInch);

      expect(layout.cols * layout.rows, greaterThanOrEqualTo(8));
      expect(layout.cols, 4);
      expect(layout.rows, 2);
      expect(layout.sheet.width, PaperSize.sixInch.widthPx(300));
      expect(layout.sheet.height, PaperSize.sixInch.heightPx(300));
    });

    test('相纸背景为白色且裁切线可见', () {
      final PixelBuffer photo = fakePortrait(295, 413);
      final SheetLayout layout =
          LayoutService.buildSheet(photo, copies: 4, paper: PaperSize.sixInch);
      // 四角应该是白纸
      expect(layout.sheet.argbAt(0, 0), 0xFFFFFFFF);
      expect(layout.sheet.argbAt(layout.sheet.width - 1, layout.sheet.height - 1),
          0xFFFFFFFF);
    });

    test('关闭裁切线不影响主体生成', () {
      final PixelBuffer photo = fakePortrait(295, 413);
      final SheetLayout layout = LayoutService.buildSheet(
        photo,
        copies: 6,
        paper: PaperSize.fiveInch,
        cutLines: false,
      );
      expect(layout.copies, 6);
      expect(layout.sheet.width, PaperSize.fiveInch.widthPx(300));
    });

    test('副本数不会超过网格容量', () {
      final PixelBuffer photo = fakePortrait(295, 413);
      final SheetLayout layout =
          LayoutService.buildSheet(photo, copies: 16, paper: PaperSize.fiveInch);
      expect(layout.copies, layout.cols * layout.rows);
    });

    test('混排：4 张不同长宽比照片都排得下且保持各自比例', () {
      final List<PixelBuffer> photos = <PixelBuffer>[
        fakePortrait(295, 413),
        fakePortrait(600, 200),
        fakePortrait(200, 600),
        fakePortrait(300, 300),
      ];
      final SheetLayout layout = LayoutService.buildMixedSheet(photos);

      expect(layout.copies, 4);
      expect(layout.cols * layout.rows, greaterThanOrEqualTo(4));
      expect(layout.photoWidths.length, 4);
      expect(layout.sheet.width, PaperSize.sixInch.widthPx(300));
      expect(layout.sheet.height, PaperSize.sixInch.heightPx(300));

      for (int i = 0; i < photos.length; i++) {
        final double src = photos[i].width / photos[i].height;
        final double dst = layout.photoWidths[i] / layout.photoHeights[i];
        expect(dst, closeTo(src, 0.05), reason: '第 ${i + 1} 张被拉伸了');
      }
    });

    test('混排：关掉裁切线时相纸四角仍是白纸', () {
      final List<PixelBuffer> photos = <PixelBuffer>[
        fakePortrait(295, 413),
        fakePortrait(600, 200),
      ];
      final SheetLayout layout =
          LayoutService.buildMixedSheet(photos, cutLines: false);
      expect(layout.sheet.argbAt(0, 0), 0xFFFFFFFF);
      expect(
        layout.sheet.argbAt(layout.sheet.width - 1, layout.sheet.height - 1),
        0xFFFFFFFF,
      );
    });

    test('混排：空列表不崩溃', () {
      final SheetLayout layout =
          LayoutService.buildMixedSheet(<PixelBuffer>[]);
      expect(layout.copies, 0);
      expect(layout.sheet.width, PaperSize.sixInch.widthPx(300));
    });

    test('混排：8 张同尺寸照片与单张重复得到同一个网格', () {
      final PixelBuffer photo = fakePortrait(295, 413);
      final SheetLayout mixed =
          LayoutService.buildMixedSheet(List<PixelBuffer>.filled(8, photo));
      expect('${mixed.cols}x${mixed.rows}', '4x2');
    });
  });
}
