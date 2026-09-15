/// 证件照底色方案。
///
/// 颜色以 `0xRRGGBB` 整数保存（不依赖 Flutter），由 UI 层转换成 `Color`。
class BgSwatch {
  const BgSwatch({
    required this.id,
    required this.name,
    required this.color,
    this.color2,
    this.transparent = false,
  });

  final String id;
  final String name;

  /// 起始色（或纯色），0xRRGGBB。
  final int color;

  /// 非空表示竖向渐变底色的结束色。
  final int? color2;

  /// 透明背景（只能导出 PNG）。
  final bool transparent;

  bool get isGradient => color2 != null;

  int get r => (color >> 16) & 0xFF;
  int get g => (color >> 8) & 0xFF;
  int get b => color & 0xFF;

  int? get r2 => color2 == null ? null : (color2! >> 16) & 0xFF;
  int? get g2 => color2 == null ? null : (color2! >> 8) & 0xFF;
  int? get b2 => color2 == null ? null : color2! & 0xFF;

  String get hex => '#${color.toRadixString(16).padLeft(6, '0').toUpperCase()}';

  /// 按纵向进度 [t]（0..1）取色，用于渐变底色。
  List<int> colorAt(double t) {
    if (color2 == null) return <int>[r, g, b];
    return <int>[
      (r + ((r2! - r) * t)).round(),
      (g + ((g2! - g) * t)).round(),
      (b + ((b2! - b) * t)).round(),
    ];
  }
}

/// 内置底色库。蓝色/红色取国内证件照冲印的常用标准色值。
class BgSwatches {
  BgSwatches._();

  static const BgSwatch white = BgSwatch(
    id: 'white',
    name: '纯白',
    color: 0xFFFFFF,
  );

  static const BgSwatch blue = BgSwatch(
    id: 'blue',
    name: '标准蓝',
    color: 0x438EDB,
  );

  static const BgSwatch blueDeep = BgSwatch(
    id: 'blue_deep',
    name: '深蓝',
    color: 0x18579D,
  );

  static const BgSwatch blueLight = BgSwatch(
    id: 'blue_light',
    name: '浅蓝',
    color: 0xA9C9EC,
  );

  static const BgSwatch red = BgSwatch(
    id: 'red',
    name: '标准红',
    color: 0xD9001B,
  );

  static const BgSwatch redBright = BgSwatch(
    id: 'red_bright',
    name: '大红',
    color: 0xFF2B2B,
  );

  static const BgSwatch gray = BgSwatch(
    id: 'gray',
    name: '浅灰',
    color: 0xE3E6EB,
  );

  static const BgSwatch gradientBlue = BgSwatch(
    id: 'gradient_blue',
    name: '渐变蓝',
    color: 0xD8E8FA,
    color2: 0x7FA8D6,
  );

  static const BgSwatch gradientGray = BgSwatch(
    id: 'gradient_gray',
    name: '渐变灰',
    color: 0xF2F4F7,
    color2: 0xC6CBD4,
  );

  static const BgSwatch transparent = BgSwatch(
    id: 'transparent',
    name: '透明',
    color: 0x000000,
    transparent: true,
  );

  static const List<BgSwatch> all = <BgSwatch>[
    white,
    blue,
    blueDeep,
    blueLight,
    red,
    redBright,
    gray,
    gradientBlue,
    gradientGray,
    transparent,
  ];

  static BgSwatch byId(String id) =>
      all.firstWhere((BgSwatch s) => s.id == id, orElse: () => white);
}
