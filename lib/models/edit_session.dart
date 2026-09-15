import '../core/constants/bg_swatches.dart';
import '../core/constants/photo_specs.dart';
import '../core/utils/pixel_buffer.dart';
import '../services/encode_service.dart';
import '../services/segmentation_service.dart';

/// 一次证件照制作过程中共享的编辑状态。
///
/// 各个页面（裁剪 / 换底 / 导出）读写同一个实例，因此「上一步」返回时
/// 之前的调整都还在。所有耗时结果（裁剪图、掩膜、合成图、编码结果）都做了
/// 缓存，参数没变就不会重复计算。
class EditSession {
  EditSession({
    required this.source,
    required this.sourceName,
    required PhotoSpec spec,
    this.dpi = 300,
  })  : spec = spec,
        swatch = BgSwatches.byId(spec.defaultSwatchId) {
    working = source;
  }

  /// 归一化后的原图（最长边 <= 2400px，未应用旋转/镜像）。
  final PixelBuffer source;

  final String sourceName;

  /// 目标规格。
  PhotoSpec spec;

  /// 冲印分辨率。
  int dpi;

  /// 应用了旋转 / 镜像之后的工作图，裁剪与抠图都基于它。
  late PixelBuffer working;

  // ------------------------------------------------ 裁剪

  int rotationQuarters = 0;
  bool flipH = false;

  double cropX = 0;
  double cropY = 0;
  double cropW = 0;

  bool _cropReady = false;
  PixelBuffer? _cropped;
  String? _croppedKey;

  /// 裁剪框的高度由规格宽高比锁定。
  double get cropH => cropW / spec.aspectRatio;

  /// 裁剪框允许的最大宽度（铺满整张图时不越界）。
  double get maxCropW {
    final double byWidth = working.width.toDouble();
    final double byHeight = working.height * spec.aspectRatio;
    return byWidth < byHeight ? byWidth : byHeight;
  }

  double get minCropW {
    final double m = maxCropW * 0.15;
    return m < 24.0 ? 24.0 : m;
  }

  /// 放大倍数（1.0 表示裁剪框已经铺满图片的最大范围）。
  double get zoom => maxCropW / cropW;

  void mutateTransform({int? rotateDelta, bool? flip}) {
    if (rotateDelta != null) {
      rotationQuarters = (rotationQuarters + rotateDelta) % 4;
    }
    if (flip != null) flipH = flip;
    _rebuildWorking();
  }

  void resetTransform() {
    rotationQuarters = 0;
    flipH = false;
    _rebuildWorking();
  }

  void _rebuildWorking() {
    PixelBuffer b = source;
    if (rotationQuarters != 0) {
      b = ImageOps.rotateQuarters(b, rotationQuarters);
    }
    if (flipH) {
      b = ImageOps.flipHorizontal(b);
    }
    working = b;
    _cropReady = false;
    _cropped = null;
    _croppedKey = null;
    // 几何变了，掩膜也失效
    mask = null;
    composited = null;
    encoded = null;
  }

  void ensureCropInitialized() {
    if (_cropReady) return;
    cropW = maxCropW;
    cropX = (working.width - cropW) / 2;
    cropY = (working.height - cropH) / 2;
    _cropReady = true;
  }

  void setCrop({required double x, required double y, required double w}) {
    final double clampedW = w.clamp(minCropW, maxCropW);
    final double h = clampedW / spec.aspectRatio;
    cropW = clampedW;
    cropX = x.clamp(0.0, (working.width - clampedW).clamp(0.0, double.infinity));
    cropY = y.clamp(0.0, (working.height - h).clamp(0.0, double.infinity));
    _cropReady = true;
  }

  /// 把当前裁剪框应用到工作图，输出规格要求的精确像素尺寸。
  PixelBuffer renderCrop({bool force = false}) {
    ensureCropInitialized();
    final String key =
        '$cropX,$cropY,$cropW,${spec.id},$dpi,${working.width}x${working.height}';
    if (!force && _cropped != null && _croppedKey == key) return _cropped!;

    _cropped = ImageOps.resampleRegion(
      working,
      cropX,
      cropY,
      cropW,
      cropH,
      spec.pixelWidth(dpi),
      spec.pixelHeight(dpi),
    );
    _croppedKey = key;
    mask = null;
    composited = null;
    encoded = null;
    return _cropped!;
  }

  PixelBuffer? get croppedCache => _cropped;

  // ------------------------------------------------ 换底色

  /// 是否把抠图换底应用到最终输出。
  bool bgEnabled = true;

  BgSwatch swatch;

  int tolerance = 34;
  int edgeClean = 1;
  int feather = 1;

  /// 手动指定的背景色 0xRRGGBB；为空则自动识别。
  int? seedColor;

  MaskResult? mask;
  PixelBuffer? composited;

  SegmentOptions get segmentOptions => SegmentOptions(
        tolerance: tolerance,
        edgeClean: edgeClean,
        feather: feather,
        seedColor: seedColor,
      );

  /// 手工画笔修补后掩膜会失效，需要重新合成。
  void invalidateComposite() {
    composited = null;
    encoded = null;
  }

  /// 参数变了，掩膜需要重算。
  void invalidateMask() {
    mask = null;
    composited = null;
    encoded = null;
  }

  /// 换底色的「底图」：没开换底时就是裁剪结果本身。
  PixelBuffer get baseImage => _cropped ?? renderCrop();

  /// 预览用图：开换底时为合成结果，否则为裁剪结果。
  PixelBuffer get previewImage => bgEnabled ? (composited ?? baseImage) : baseImage;

  /// 需要导出的图：透明底统一留 alpha，其余情况已经是 RGB。
  PixelBuffer get outputImage =>
      bgEnabled && composited != null ? composited! : baseImage;

  // ------------------------------------------------ 压缩

  /// 输出格式。透明底色只能是 PNG。
  bool forcePng = false;
  bool get asPng => forcePng || (bgEnabled && swatch.transparent);

  int quality = 92;

  /// 目标体积（KB）。非空时优先按体积压缩。
  int? targetKb;

  EncodedImage? encoded;

  bool get sizeLocked => targetKb != null && targetKb! > 0;

  void invalidateEncoded() {
    encoded = null;
  }

  // ------------------------------------------------ 排版

  int sheetCopies = 8;
  bool sheetCutLines = true;

  /// 文件名用的人话标签。
  String get fileBaseName {
    final String size = spec.name;
    final String bg = bgEnabled ? swatch.name : '原图';
    return '${size}_$bg';
  }

  /// 供界面展示的一句话摘要。
  String get summaryLabel =>
      '${spec.name} · ${spec.mmLabel} · ${spec.pxLabel(dpi)}';
}
