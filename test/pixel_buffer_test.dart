import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:id_photo_maker/core/utils/pixel_buffer.dart';

PixelBuffer solid(int w, int h, int r, int g, int b, [int a = 255]) {
  final PixelBuffer buf = PixelBuffer.empty(w, h);
  ImageOps.fillColor(buf, r, g, b, a);
  return buf;
}

void main() {
  group('PixelBuffer', () {
    test('构造时校验缓冲区长度', () {
      expect(
        () => PixelBuffer(2, 2, Uint8List(4)),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => PixelBuffer(2, 2, Uint8List(16)),
        returnsNormally,
      );
    });

    test('argbAt / setRgba 往返一致', () {
      final PixelBuffer buf = PixelBuffer.empty(4, 3);
      buf.setRgba(2, 1, 0x11, 0x22, 0x33, 0xFF);
      expect(buf.argbAt(2, 1), 0xFF112233);
      expect(buf.rgba[buf.indexOf(2, 1)], 0x11);
    });

    test('hasTransparency 能识别非全不透明像素', () {
      expect(solid(2, 2, 1, 2, 3).hasTransparency, isFalse);
      final PixelBuffer t = solid(2, 2, 1, 2, 3, 100);
      expect(t.hasTransparency, isTrue);
    });
  });

  group('ImageOps.rotateQuarters', () {
    test('0 度返回等价副本', () {
      final PixelBuffer src = solid(3, 2, 10, 20, 30);
      final PixelBuffer out = ImageOps.rotateQuarters(src, 0);
      expect(out.width, 3);
      expect(out.height, 2);
      expect(out.rgba, equals(src.rgba));
    });

    test('90/180/270 度尺寸与角点位置正确', () {
      // 用四个不同的角做标记，验证旋转后的朝向
      final PixelBuffer src = PixelBuffer.empty(2, 3); // w=2, h=3
      ImageOps.fillColor(src, 0, 0, 0);
      src.setRgba(0, 0, 255, 0, 0, 255); // 左上: 红
      src.setRgba(1, 0, 0, 255, 0, 255); // 右上: 绿

      final PixelBuffer q1 = ImageOps.rotateQuarters(src, 1); // 顺时针 90
      expect(q1.width, 3);
      expect(q1.height, 2);
      // 原左上(红) 应落到新图的右上
      expect(q1.argbAt(2, 0), 0xFFFF0000);
      // 原右上(绿) 应落到新图的右下
      expect(q1.argbAt(2, 1), 0xFF00FF00);

      final PixelBuffer q2 = ImageOps.rotateQuarters(src, 2);
      expect(q2.width, 2);
      expect(q2.height, 3);
      expect(q2.argbAt(1, 2), 0xFFFF0000);

      final PixelBuffer q3 = ImageOps.rotateQuarters(src, 3);
      expect(q3.width, 3);
      expect(q3.height, 2);
      expect(q3.argbAt(0, 1), 0xFFFF0000);
    });

    test('旋转 4 次回到原图', () {
      final PixelBuffer src = solid(5, 4, 77, 88, 99);
      final PixelBuffer out = ImageOps.rotateQuarters(src, 4);
      expect(out.width, src.width);
      expect(out.height, src.height);
      expect(out.rgba, equals(src.rgba));
    });

    test('负角度等价于正向补角', () {
      final PixelBuffer src = solid(4, 3, 1, 2, 3);
      final PixelBuffer a = ImageOps.rotateQuarters(src, -1);
      final PixelBuffer b = ImageOps.rotateQuarters(src, 3);
      expect(a.rgba, equals(b.rgba));
    });
  });

  group('ImageOps.flip', () {
    test('水平镜像交换左右', () {
      final PixelBuffer src = PixelBuffer.empty(3, 1);
      src.setRgba(0, 0, 1, 1, 1, 255);
      src.setRgba(2, 0, 9, 9, 9, 255);
      final PixelBuffer out = ImageOps.flipHorizontal(src);
      expect(out.argbAt(0, 0), 0xFF090909);
      expect(out.argbAt(2, 0), 0xFF010101);
    });

    test('垂直镜像交换上下', () {
      final PixelBuffer src = PixelBuffer.empty(1, 3);
      src.setRgba(0, 0, 1, 1, 1, 255);
      src.setRgba(0, 2, 9, 9, 9, 255);
      final PixelBuffer out = ImageOps.flipVertical(src);
      expect(out.argbAt(0, 0), 0xFF090909);
      expect(out.argbAt(0, 2), 0xFF010101);
    });
  });

  group('ImageOps.resampleRegion', () {
    test('降采样取区域平均色', () {
      final PixelBuffer src = PixelBuffer.empty(4, 4);
      // 左半边黑，右半边白
      for (int y = 0; y < 4; y++) {
        for (int x = 0; x < 4; x++) {
          final int v = x < 2 ? 0 : 255;
          src.setRgba(x, y, v, v, v, 255);
        }
      }
      final PixelBuffer out =
          ImageOps.resampleRegion(src, 0, 0, 4, 4, 2, 2);
      expect(out.width, 2);
      expect(out.height, 2);
      expect(out.argbAt(0, 0), 0xFF000000);
      expect(out.argbAt(1, 0), 0xFFFFFFFF);
    });

    test('取局部区域并输出指定尺寸', () {
      final PixelBuffer src = PixelBuffer.empty(10, 10);
      ImageOps.fillColor(src, 0, 0, 0);
      for (int y = 2; y < 6; y++) {
        for (int x = 2; x < 6; x++) {
          src.setRgba(x, y, 200, 100, 50, 255);
        }
      }
      final PixelBuffer out = ImageOps.resampleRegion(src, 2, 2, 4, 4, 20, 20);
      expect(out.width, 20);
      expect(out.height, 20);
      expect(out.argbAt(10, 10), 0xFFC86432);
    });

    test('放大使用双线性插值不会越界', () {
      final PixelBuffer src = solid(3, 3, 120, 130, 140);
      final PixelBuffer out = ImageOps.resampleRegion(src, 0, 0, 3, 3, 9, 9);
      expect(out.argbAt(4, 4), 0xFF78828C);
      expect(out.argbAt(0, 0), 0xFF78828C);
      expect(out.argbAt(8, 8), 0xFF78828C);
    });
  });

  group('ImageOps.blit', () {
    test('按坐标贴图并正确处理越界', () {
      final PixelBuffer canvas = solid(6, 6, 0, 0, 0);
      final PixelBuffer patch = solid(4, 4, 255, 255, 255);
      ImageOps.blit(canvas, patch, 4, 4); // 右下角只贴得进 2x2
      expect(canvas.argbAt(5, 5), 0xFFFFFFFF);
      expect(canvas.argbAt(4, 4), 0xFFFFFFFF);
      expect(canvas.argbAt(3, 3), 0xFF000000);
    });

    test('负坐标贴图', () {
      final PixelBuffer canvas = solid(6, 6, 0, 0, 0);
      final PixelBuffer patch = solid(4, 4, 255, 255, 255);
      ImageOps.blit(canvas, patch, -2, -2);
      expect(canvas.argbAt(0, 0), 0xFFFFFFFF);
      expect(canvas.argbAt(1, 1), 0xFFFFFFFF);
      expect(canvas.argbAt(2, 2), 0xFF000000);
    });

    test('全透明像素默认被跳过', () {
      final PixelBuffer canvas = solid(2, 2, 0, 0, 0);
      final PixelBuffer patch = solid(2, 2, 255, 255, 255, 0);
      ImageOps.blit(canvas, patch, 0, 0);
      expect(canvas.argbAt(0, 0), 0xFF000000);
    });
  });
}
