/// 证件照的物理规格（毫米 + DPI），并可据此推导出精确的像素尺寸。
///
/// 像素换算公式：`px = mm / 25.4 * dpi`，这是冲印行业的标准换算方式。
/// 部分规格（如美国签证）官方直接规定像素值，用 [pxWidthOverride] 覆盖。
class PhotoSpec {
  const PhotoSpec({
    required this.id,
    required this.name,
    required this.widthMm,
    required this.heightMm,
    required this.category,
    this.dpi = 300,
    this.pxWidthOverride,
    this.pxHeightOverride,
    this.note = '',
    this.defaultSwatchId = 'white',
  });

  final String id;
  final String name;
  final double widthMm;
  final double heightMm;
  final String category;

  /// 冲印分辨率，证件照行业默认 300 DPI。
  final int dpi;

  final int? pxWidthOverride;
  final int? pxHeightOverride;

  /// 备注，例如「蓝底/白底均可」。
  final String note;

  /// 该规格最常见的底色。
  final String defaultSwatchId;

  double get aspectRatio => widthMm / heightMm;

  int pixelWidth(int dpi) =>
      pxWidthOverride ?? (widthMm / 25.4 * dpi).round();

  int pixelHeight(int dpi) =>
      pxHeightOverride ?? (heightMm / 25.4 * dpi).round();

  /// 例如 `25×35mm`。
  String get mmLabel {
    String fmt(double v) =>
        v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    return '${fmt(widthMm)}×${fmt(heightMm)}mm';
  }

  /// 例如 `295×413px`。
  String pxLabel(int dpi) => '${pixelWidth(dpi)}×${pixelHeight(dpi)}px';

  /// 例如 `一寸 25×35mm · 295×413px`。
  String get fullLabel => '$name  $mmLabel';

  @override
  String toString() => '$name($mmLabel)';
}

/// 常用证件照规格库。
///
/// 数据来源为国内照片冲印行业通用尺寸，以及各国签证/考试报名系统的官方要求。
class PhotoSpecs {
  PhotoSpecs._();

  static const String categoryCommon = '常用';
  static const String categoryId = '证件';
  static const String categoryVisa = '签证';
  static const String categoryExam = '考试';

  static const List<PhotoSpec> all = <PhotoSpec>[
    // ---------------- 常用 ----------------
    PhotoSpec(
      id: 'one_inch',
      name: '一寸',
      widthMm: 25,
      heightMm: 35,
      category: categoryCommon,
      note: '最通用，简历/证件首选',
      defaultSwatchId: 'blue',
    ),
    PhotoSpec(
      id: 'two_inch',
      name: '二寸',
      widthMm: 35,
      heightMm: 49,
      category: categoryCommon,
      note: '毕业证、工作证常用',
      defaultSwatchId: 'blue',
    ),
    PhotoSpec(
      id: 'small_one_inch',
      name: '小一寸',
      widthMm: 22,
      heightMm: 32,
      category: categoryCommon,
      note: '驾驶证、部分工作证',
      defaultSwatchId: 'white',
    ),
    PhotoSpec(
      id: 'big_one_inch',
      name: '大一寸',
      widthMm: 33,
      heightMm: 48,
      category: categoryCommon,
      note: '护照、部分考试',
      defaultSwatchId: 'white',
    ),
    PhotoSpec(
      id: 'small_two_inch',
      name: '小二寸',
      widthMm: 35,
      heightMm: 45,
      category: categoryCommon,
      note: '学位照、部分签证',
      defaultSwatchId: 'blue',
    ),
    PhotoSpec(
      id: 'big_two_inch',
      name: '大二寸',
      widthMm: 35,
      heightMm: 53,
      category: categoryCommon,
      note: '部分职称评审',
      defaultSwatchId: 'blue',
    ),

    // ---------------- 证件 ----------------
    PhotoSpec(
      id: 'id_card',
      name: '身份证',
      widthMm: 26,
      heightMm: 32,
      category: categoryId,
      dpi: 350,
      note: '358×441px @350DPI',
      defaultSwatchId: 'white',
    ),
    PhotoSpec(
      id: 'social_card',
      name: '社保卡',
      widthMm: 26,
      heightMm: 32,
      category: categoryId,
      dpi: 350,
      note: '与身份证同规格',
      defaultSwatchId: 'white',
    ),
    PhotoSpec(
      id: 'driver_license',
      name: '驾驶证',
      widthMm: 22,
      heightMm: 32,
      category: categoryId,
      note: '需白底',
      defaultSwatchId: 'white',
    ),
    PhotoSpec(
      id: 'passport',
      name: '护照',
      widthMm: 33,
      heightMm: 48,
      category: categoryId,
      note: '白底，不允许露齿',
      defaultSwatchId: 'white',
    ),
    PhotoSpec(
      id: 'hk_macao_permit',
      name: '港澳通行证',
      widthMm: 33,
      heightMm: 48,
      category: categoryId,
      defaultSwatchId: 'white',
    ),
    PhotoSpec(
      id: 'marriage_cert',
      name: '结婚证',
      widthMm: 53,
      heightMm: 35,
      category: categoryId,
      note: '横版 2 寸，常用红底',
      defaultSwatchId: 'red',
    ),
    PhotoSpec(
      id: 'degree',
      name: '学位照',
      widthMm: 35,
      heightMm: 45,
      category: categoryId,
      note: '常用蓝底',
      defaultSwatchId: 'blue',
    ),
    PhotoSpec(
      id: 'teacher_cert',
      name: '教师资格证',
      widthMm: 41,
      heightMm: 54,
      category: categoryId,
      defaultSwatchId: 'white',
    ),

    // ---------------- 签证 ----------------
    PhotoSpec(
      id: 'us_visa',
      name: '美国签证',
      widthMm: 50.8,
      heightMm: 50.8,
      category: categoryVisa,
      pxWidthOverride: 600,
      pxHeightOverride: 600,
      note: '2×2 英寸 / 600×600px',
      defaultSwatchId: 'white',
    ),
    PhotoSpec(
      id: 'japan_visa',
      name: '日本签证',
      widthMm: 45,
      heightMm: 45,
      category: categoryVisa,
      note: '白底，方形',
      defaultSwatchId: 'white',
    ),
    PhotoSpec(
      id: 'schengen_visa',
      name: '申根签证',
      widthMm: 35,
      heightMm: 45,
      category: categoryVisa,
      note: '欧洲通用',
      defaultSwatchId: 'white',
    ),
    PhotoSpec(
      id: 'korea_visa',
      name: '韩国签证',
      widthMm: 35,
      heightMm: 45,
      category: categoryVisa,
      note: '白底',
      defaultSwatchId: 'white',
    ),
    PhotoSpec(
      id: 'uk_visa',
      name: '英国签证',
      widthMm: 35,
      heightMm: 45,
      category: categoryVisa,
      note: '浅灰或白底',
      defaultSwatchId: 'gray',
    ),

    // ---------------- 考试 ----------------
    PhotoSpec(
      id: 'postgraduate',
      name: '考研报名',
      widthMm: 41,
      heightMm: 54,
      category: categoryExam,
      note: '蓝底或白底',
      defaultSwatchId: 'blue',
    ),
    PhotoSpec(
      id: 'civil_servant',
      name: '公务员报名',
      widthMm: 25,
      heightMm: 35,
      category: categoryExam,
      defaultSwatchId: 'blue',
    ),
    PhotoSpec(
      id: 'cet',
      name: '英语四六级',
      widthMm: 33,
      heightMm: 48,
      category: categoryExam,
      note: '蓝底或白底',
      defaultSwatchId: 'blue',
    ),
    PhotoSpec(
      id: 'ncre',
      name: '计算机等级考试',
      widthMm: 33,
      heightMm: 48,
      category: categoryExam,
      defaultSwatchId: 'blue',
    ),
    PhotoSpec(
      id: 'nurse_exam',
      name: '护士执业资格',
      widthMm: 25,
      heightMm: 35,
      category: categoryExam,
      defaultSwatchId: 'white',
    ),
    PhotoSpec(
      id: 'constructor_exam',
      name: '建造师考试',
      widthMm: 25,
      heightMm: 35,
      category: categoryExam,
      defaultSwatchId: 'blue',
    ),

    // ---------------- 其他 ----------------
    PhotoSpec(
      id: 'resume',
      name: '简历照',
      widthMm: 25,
      heightMm: 35,
      category: '其他',
      note: '与一寸同规格',
      defaultSwatchId: 'blue',
    ),
    PhotoSpec(
      id: 'custom',
      name: '自定义',
      widthMm: 35,
      heightMm: 45,
      category: '其他',
      note: '尺寸自由调整',
      defaultSwatchId: 'white',
    ),
  ];

  static PhotoSpec byId(String id) =>
      all.firstWhere((PhotoSpec s) => s.id == id, orElse: () => all.first);

  static List<PhotoSpec> byCategory(String category) =>
      all.where((PhotoSpec s) => s.category == category).toList();

  static List<PhotoSpec> get common => byCategory(categoryCommon);

  static List<String> get categories {
    final List<String> result = <String>[];
    for (final PhotoSpec s in all) {
      if (!result.contains(s.category)) result.add(s.category);
    }
    return result;
  }

  /// 支持的冲印分辨率。
  static const List<int> supportedDpi = <int>[300, 350, 600];
}
