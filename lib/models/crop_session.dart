import '../core/constants/photo_specs.dart';
import '../core/utils/pixel_buffer.dart';

/// 一张照片的「裁剪会话」。
///
/// 只负责取景（旋转 / 镜像 / 裁剪框）与输出像素尺寸，不掺换底色、压缩、排版。
/// 之所以从原来铁板一块的 `EditSession` 里拆出来：「裁剪大小」「换底色（裁剪可选）」
/// 「拼图（逐张裁剪）」三个**独立**工具可以共用同一套裁剪逻辑，而各自只持有
/// 自己真正需要的状态。
class CropSession {
  CropSession({
    required this.source,
    required this.sourceName,
    required PhotoSpec spec,
    this.cropEnabled = true,
  })  : _spec = spec,
        _dpi = spec.dpi {
    working = source;
  }

  /// 归一化后的原图（最长边 <= 2400px，未应用旋转 / 镜像）。
  final PixelBuffer source;

  final String sourceName;

  PhotoSpec _spec;
  PhotoSpec get spec => _spec;

  int _dpi;

  /// 输出用的冲印分辨率。切换规格时会跟着规格走（身份证 350、签证 600）。
  int get dpi => _dpi;

  /// 是否启用裁剪。
  ///
  /// 为 `false` 时 [baseImage] 直接给出工作图本身 —— 「换底色」这种裁剪可有可无
  /// 的功能就靠它：用户只想去掉蓝底，不想改尺寸，不该被强塞一次裁剪。
  bool cropEnabled;

  /// 应用了旋转 / 镜像之后的工作图，裁剪与抠图都基于它。
  late PixelBuffer working;

  // ------------------------------------------------ 变换

  int rotationQuarters = 0;
  bool flipH = false;

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
    if (rotationQuarters != 0) b = ImageOps.rotateQuarters(b, rotationQuarters);
    if (flipH) b = ImageOps.flipHorizontal(b);
    working = b;
    _invalidateCrop();
  }

  // ------------------------------------------------ 规格

  /// 切换目标规格。dpi 一并跟随，避免出现「选了身份证（350DPI）却按 300 输出」。
  void setSpec(PhotoSpec next) {
    _spec = next;
    _dpi = next.dpi;
    _invalidateCrop();
  }

  void _invalidateCrop() {
    _cropReady = false;
    _cropped = null;
    _croppedKey = null;
  }

  // ------------------------------------------------ 裁剪框

  double cropX = 0;
  double cropY = 0;
  double cropW = 0;

  bool _cropReady = false;
  PixelBuffer? _cropped;
  String? _croppedKey;

  /// 裁剪框的高度由规格宽高比锁定。
  double get cropH => cropW / _spec.aspectRatio;

  /// 裁剪框允许的最大宽度（铺满整张图时不越界）。
  double get maxCropW {
    final double byWidth = working.width.toDouble();
    final double byHeight = working.height * _spec.aspectRatio;
    return byWidth < byHeight ? byWidth : byHeight;
  }

  double get minCropW {
    final double m = maxCropW * 0.15;
    return m < 24.0 ? 24.0 : m;
  }

  /// 放大倍数（1.0 表示裁剪框已经铺满图片的最大范围）。
  double get zoom => cropW <= 0 ? 1 : maxCropW / cropW;

  void ensureCropInitialized() {
    if (_cropReady) return;
    cropW = maxCropW;
    cropX = (working.width - cropW) / 2;
    cropY = (working.height - cropH) / 2;
    _cropReady = true;
  }

  void setCrop({required double x, required double y, required double w}) {
    final double clampedW = w.clamp(minCropW, maxCropW);
    final double h = clampedW / _spec.aspectRatio;
    cropW = clampedW;
    cropX = x.clamp(0.0, (working.width - clampedW).clamp(0.0, double.infinity));
    cropY = y.clamp(0.0, (working.height - h).clamp(0.0, double.infinity));
    _cropReady = true;
  }

  /// 把当前裁剪框应用到工作图，输出规格要求的精确像素尺寸。
  ///
  /// 缓存键里带上**最终像素尺寸**而不是 `spec.id` —— 自定义规格的 id 固定是
  /// `custom`，但宽高随时会变，只按 id 做键会把上一次的成片当成这次的。
  PixelBuffer renderCrop({bool force = false}) {
    ensureCropInitialized();
    final String key = '$cropX,$cropY,$cropW,'
        '${_spec.pixelWidth(_dpi)}x${_spec.pixelHeight(_dpi)},'
        '${working.width}x${working.height}';
    if (!force && _cropped != null && _croppedKey == key) return _cropped!;

    _cropped = ImageOps.resampleRegion(
      working,
      cropX,
      cropY,
      cropW,
      cropH,
      _spec.pixelWidth(_dpi),
      _spec.pixelHeight(_dpi),
    );
    _croppedKey = key;
    return _cropped!;
  }

  PixelBuffer? get croppedCache => _cropped;

  /// 后续处理（换底 / 编码 / 排版）的底图：没启用裁剪时就是工作图本身。
  PixelBuffer get baseImage => cropEnabled ? renderCrop() : working;

  /// 界面展示用的一句话摘要。
  String get summaryLabel => cropEnabled
      ? '${_spec.name} · ${_spec.mmLabel} · ${_spec.pxLabel(_dpi)}'
      : '原始尺寸 ${working.width}×${working.height}px';
}
