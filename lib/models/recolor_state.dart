import '../core/constants/bg_swatches.dart';
import '../core/utils/pixel_buffer.dart';
import '../services/segmentation_service.dart';

/// 「换底色」的全部状态：掩膜、抠图参数、合成结果。
///
/// 与 [CropSession] 解耦 —— 换底色工具只管把一张底图上的背景替换掉，
/// 底图从哪来（裁剪结果 / 原图）由调用方决定。
class RecolorState {
  RecolorState({String swatchId = 'white'})
      : swatch = BgSwatches.byId(swatchId);

  /// 是否把换底结果应用到最终输出。关掉就是「只抠图不换底」。
  bool enabled = true;

  BgSwatch swatch;

  int tolerance = 34;
  int edgeClean = 1;
  int feather = 1;

  /// 手动指定的背景色 0xRRGGBB；为空则自动识别。
  int? seedColor;

  MaskResult? mask;
  PixelBuffer? composited;

  SegmentOptions get options => SegmentOptions(
        tolerance: tolerance,
        edgeClean: edgeClean,
        feather: feather,
        seedColor: seedColor,
      );

  /// 输出是否为透明底（只能出 PNG）。
  bool get transparentOutput => enabled && swatch.transparent;

  /// 手工画笔修补后掩膜会失效，需要重新合成。
  void invalidateComposite() => composited = null;

  /// 参数变了，掩膜需要重算。
  void invalidateMask() {
    mask = null;
    composited = null;
  }

  /// 预览用图：开换底时为合成结果，否则为底图本身。
  PixelBuffer previewOn(PixelBuffer base) =>
      enabled ? (composited ?? base) : base;

  /// 需要导出的图。
  PixelBuffer outputOn(PixelBuffer base) =>
      enabled && composited != null ? composited! : base;

  /// 回到出厂参数。
  void reset() {
    seedColor = null;
    tolerance = 34;
    edgeClean = 1;
    feather = 1;
    invalidateMask();
  }
}
