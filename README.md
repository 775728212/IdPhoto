# 证件照 App（Flutter）

一个纯本地运行的证件照制作工具：**按标准规格裁剪 → 智能换底色 → 按目标体积压缩 → 一键排版打印**。
不依赖任何云端服务，所有图像处理都在手机上完成。

---

## 一、功能

| 模块 | 能力 |
| --- | --- |
| **裁剪** | 30+ 标准规格（一寸/二寸/小一寸/大一寸/护照/身份证/社保卡/驾驶证/结婚证/美国签证/申根签证/考研/公务员/四六级…），按 `mm ÷ 25.4 × DPI` 精确换算像素；双指缩放、单指拖动；左右旋转 90°、水平镜像；证件照构图参考线（头顶留白 10% / 下巴 62%）与三分网格 |
| **换底色** | 基于**边界洪水填充**的自动抠图；10 种内置底色（纯白 / 标准蓝 / 深蓝 / 浅蓝 / 标准红 / 大红 / 浅灰 / 渐变蓝 / 渐变灰 / 透明）；三点精细控制（容差 / 去边缘杂色 / 边缘羽化）；吸管手动取背景色；画笔手动涂抹修补背景与前景；长按对比原图 |
| **压缩** | 两种模式——「按画质」手动拖质量条，或「按体积」输入上限（20/30/50/100/200/500 KB）后**二分搜索**出画质最好的参数；支持 JPG / PNG；实时显示成片体积 |
| **导出** | 保存到系统相册（独立相册「证件照」）、调起系统分享面板 |
| **排版打印** | 一张 5 寸 / 6 寸相纸自动排布多份（1~16 张），自动挑选占满程度最高的「列 × 行」组合，带浅灰裁切线，导出即冲印 |

---

## 二、快速开始

### 1. 前置要求

- Flutter SDK **3.38.1 或更高**（`share_plus 13` 的要求；本项目在 **3.47.4 / Dart 3.13.3** 上验证通过）
- Android：minSdk **24**（`image_picker` 要求）
- iOS：**13.0** 或更高

```bash
flutter --version   # 确认版本
flutter doctor      # 检查 Android / iOS 工具链
```

### 2. 初始化项目

```bash
cd 证件照

# 生成 android/ ios/ 等平台目录（不会覆盖已有的 lib/ 与 pubspec.yaml）
flutter create --platforms=android,ios --org com.idphoto --project-name id_photo_maker .

# 拉取依赖
flutter pub get

# 补齐相册/相机的平台权限声明（AndroidManifest.xml + Info.plist）
python tool/patch_platforms.py

# 运行
flutter run
```

> Windows 用户可直接执行 `./run.ps1`，脚本会按顺序完成上面四步。

### 3. 验证

```bash
flutter analyze                # 静态检查（当前 0 issue）
flutter test                   # 单元测试（像素运算 / 抠图 / 换底 / 压缩 / 排版）

# 无设备也能验证：纯 Dart 跑完整条算法链，导出示例图
dart run tool/verify_algorithms.dart build/verify

flutter build apk --release    # 出 Android 安装包（详见下一节）
```

### 4. 打包 APK

三条路，按可靠性排序。

**A. 云端构建 —— 本机零安装（推荐）**

仓库里已备好 `.github/workflows/build-apk.yml`。推到 GitHub 之后：

- 手动触发：仓库 **Actions** 页 → **Build APK** → **Run workflow**；
- 或打 tag 自动触发：`git tag v1.0.0 && git push --tags`。

约 6~8 分钟出包，在该次 run 页面底部下载 artifact `id-photo-maker-release-apk`，
里面就是通用 `app-release.apk`。

**B. 本机一键 —— 需要已装 Flutter + JDK 17（或 Android Studio）**

```powershell
powershell -ExecutionPolicy Bypass -File .\run.ps1 -BuildApk
# 产物：build\app\outputs\flutter-apk\app-release.apk
```

想按 ABI 拆成更小的包（每份约 8~10MB，但要按手机架构对号入座）：

```bash
flutter build apk --release --split-per-abi
```

**C. 从零补工具链 —— 约 1.5~2 小时**

若机器上连 JDK 都没有，需要依次补齐：① JDK 17 → ② Android commandline-tools →
③ `sdkmanager` 装 `platform-tools` / `build-tools` / `platforms;android-35` →
④ `flutter config --android-sdk <路径> --jdk-dir <路径>`，然后才能 `flutter build apk`。

> **2026-09-15 在这台开发机上的实测记录**
>
> - Flutter SDK 3.47.4 / Dart 3.13.3 已就绪，`bin/cache/artifacts/` 1.8GB，
>   Android 引擎产物（`android-arm64-release` 等）**已全部下载完成**；
> - **JDK、Android SDK、Gradle、Android Studio 全部缺失**；
> - 直连 `dl.google.com` / `api.adoptium.net` / `services.gradle.org` 均 HTTP 200，
>   但实测吞吐只有约 **190 KB/s**，所以补齐工具链 + Gradle/Maven 依赖预计 **1.5~2 小时**；
> - `flutter create` 在该沙箱环境下会**卡死且零输出**（`flutter --version` 却正常，
>   换全新空目录同样卡死）——APK 构建的必经步骤，因此本地打包当前不可行。

### 5. 排障：flutter 命令卡死且零输出

**先删缓存锁。** 症状是命令完全无输出、不写任何文件、看起来像在下载或检查版本。
真实原因通常是上一次 `flutter` 进程被强杀（Ctrl+C / 结束任务）后留下的排他锁：

```bash
rm -f <flutter>/bin/cache/lockfile     # Windows: <flutter>\bin\cache\lockfile
```

`run.ps1` 已内置处理：若发现锁文件超过 10 分钟未更新，会自动删掉再继续。

判断「是在下载还是卡住了」的可靠办法 —— 看 cache 有没有被写：

```bash
find <flutter>/bin/cache -newermt '-5 minutes' -type f
```

输出为空 ⇒ 它**没在下东西**，是卡住了。

---

## 三、平台权限说明

`tool/patch_platforms.py` 会自动写入下列内容，若你想手动配置，参照这里：

**`android/app/src/main/AndroidManifest.xml`**

```xml
<manifest ...>
    <!-- gal：保存到相册（API <= 29 需要写外部存储权限） -->
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"
        android:maxSdkVersion="29" />

    <application
        android:requestLegacyExternalStorage="true"
        ...>
```

> `image_picker` 走系统相机 / 相册选择器 Intent，**不需要**声明 `CAMERA` 权限，声明了反而要额外申请，这里刻意不加。

**`ios/Runner/Info.plist`**（`<dict>` 内追加）

```xml
<key>NSPhotoLibraryAddUsageDescription</key>
<string>需要保存制作好的证件照到你的相册</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>需要读取相册中的照片来制作证件照</string>
<key>NSCameraUsageDescription</key>
<string>需要使用相机拍摄证件照</string>
```

---

## 四、代码结构

```
lib/
├── main.dart                     入口：锁定竖屏 + 状态栏样式
├── app.dart                      MaterialApp 装配
│
├── core/
│   ├── constants/
│   │   ├── photo_specs.dart      30+ 证件照规格表（毫米 + DPI → 像素）
│   │   └── bg_swatches.dart      底色库（含渐变与透明）
│   ├── theme/app_theme.dart      浅色主题、色板、圆角规范
│   └── utils/
│       └── pixel_buffer.dart     ★ 统一像素载体 + 几何变换（旋转/镜像/区域重采样/贴图）
│
├── models/
│   └── edit_session.dart         ★ 跨页面共享的编辑状态（含各级结果缓存）
│
├── services/
│   ├── image_loader.dart         选图解码 + EXIF 方向烘焙 + 工作分辨率归一化
│   ├── segmentation_service.dart ★ 抠图（背景主色估计 / 洪水填充 / 膨胀 / 羽化 / 画笔）
│   ├── recolor_service.dart      ★ 换底色（含边缘去色溢与渐变底色）
│   ├── encode_service.dart       编码与压缩（JPEG 质量二分搜索）
│   ├── layout_service.dart       相纸排版
│   └── export_service.dart       保存相册 / 系统分享
│
└── ui/
    ├── pages/
    │   ├── home_page.dart        选图 + 规格选择
    │   ├── crop_page.dart        裁剪（取景框即成片）
    │   ├── background_page.dart  换底色（抠图 + 取色 + 画笔修补）
    │   └── export_page.dart      压缩 / 排版 / 保存分享
    └── widgets/
        ├── crop_canvas.dart      裁剪手势与构图参考线
        ├── pixel_buffer_view.dart PixelBuffer → ui.Image 的带缓存预览 + 棋盘格
        ├── spec_picker_sheet.dart 全规格选择面板
        └── common.dart           卡片 / 滑块 / 胶囊选择 / 底色选择 / 加载遮罩

tool/
├── verify_algorithms.dart         ★ 纯 Dart 端到端算法验证（无需设备，导出示例图）
└── patch_platforms.py             补齐 Android / iOS 权限声明（幂等）
```

---

## 五、核心实现要点

### 1. 统一用 `PixelBuffer` 而不是 `ui.Image`

所有逐像素操作（洪水填充、alpha 合成、区域重采样、alpha 通道判断）都跑在一个
`Uint8List` RGBA 缓冲区上（`core/utils/pixel_buffer.dart`）。好处：

- 读写是裸数组，抠图 + 合成分辨率 413×579 时单次耗时在毫秒级；
- 与 `package:image` 解耦，核心算法可在纯 Dart 环境下被 `flutter test` 直接覆盖；
- 只在需要显示时才 `PixelBuffer → ui.Image`（`pixel_buffer_view.dart` 按对象标识缓存，滑块拖动不会反复解码）。

原图进入流水线前会先做一次**最长边 ≤ 2400px 归一化**：证件照最终输出最大也不过 600px，
2400px 的原图余量已经非常充足，同时把内存占用从 12MP 的约 48MB 降到约 10MB。

### 2. 抠图：边界洪水填充（`segmentation_service.dart`）

针对证件照「人像 + 相对干净背景」的特点：

1. **估计背景主色**——取四角各 5% 的色块，按 5 bit/通道量化后取直方图众数。
   证件照人物居中，四个角基本都是背景，这个估计非常稳。
2. **采集种子**——只把**图片边界上颜色接近主色**的像素作为种子。
   这一步很关键：真人证件照的肩膀通常会延伸到底边，如果无条件从边界开始填充，
   人物会被当成背景吃掉；加了颜色门槛后，肩部像素不会成为种子。
3. **洪水填充**——4 邻域；除与主色比较外，还允许与「邻居颜色」比较（`localGrowth`），
   用于应对手机拍摄时背景存在光照渐变的情况。
4. **去边缘杂色**——对背景掩膜做 8 邻域膨胀 N 像素，吃掉抠图边缘残留的一圈原底色。
5. **羽化**——对掩膜做可分离盒式模糊（O(w·h)），让头发丝过渡自然。

置信度不足时（边界找不到背景像素、或背景占比 < 8%）界面会主动提示用户改用画笔手动涂抹。

### 3. 换底色：去色溢 + 颜色投影修边（`recolor_service.dart`）

抠图边缘的抗锯齿像素其实是 `前景 × (1-t) + 原底色 × t` 的混合结果。
若直接叠加新底色，从蓝底换成白底时边缘会残留一圈蓝边，所以要先反解真实前景色：

```
前景真实色 = (当前像素色 - 原背景色 × t) / (1 - t)
输出像素   = 前景真实色 × (1 - t) + 新底色 × t
```

**关键在 t 从哪来。** 掩膜经过「膨胀 + 羽化」之后，它的灰度值只是一个很粗糙的 t 估计：

| t 的来源 | 换白底后的边缘表现 |
| --- | --- |
| 不做反解（`decontaminate: false`） | 残留**淡蓝色描边** |
| 用羽化掩膜当 t（偏大） | 反解过度 → 发丝出现**紫灰色描边**、脸颊边缘出现**黄色亮线** |
| **颜色投影反解**（默认） | 干净，无彩边 |

之所以偏大就会出彩边：t 偏大时 `当前像素色 - 原背景色 × t` 会**减过头**，
蓝色通道被减成负数再截断到 0，剩下的红/绿就浮出来变成紫的、黄的。

所以默认路径改用**颜色投影**（`colorMatting: true`）来解 t：从所有「确定前景」像素
（`mask == 0`）出发做一次多源 BFS，得到每个像素「最近的前景核心色」F；
于是像素颜色 C 必然落在线段 `B(原背景色) → F` 上，直接投影取参数即可：

```
前景占比 = (C - B)·(F - B) / |F - B|²     然后 clamp 到 0..1
```

比羽化值准得多，而且顺带解决另一个问题：`edgeClean` 膨胀会把**真正的前景**误标成背景，
投影得到的占比更大时会把它「还回来」。整张图一次 BFS，O(w·h)，122k 像素耗时 1ms 量级。

渐变底色按行插值（`colorAt(y / (h-1))`），透明底色则直接输出带 alpha 的前景。
若掩膜与图像尺寸不一致（例如拿全图掩膜去合裁剪后的成片），会**直接抛 `ArgumentError`**，
而不是静默按错误偏移读出错图。

### 4. 裁剪：取景框即成片（`crop_canvas.dart`）

视口按目标规格的宽高比呈现，框内所见即导出所得——不需要再画一个遮罩去表示"被裁掉的部分"。
手势用 `onScaleStart/Update` 统一处理：记录起始焦点对应的**图像坐标**作为锚点，
缩放时保持该点不动，单指时 `scale` 恒为 1，自然退化成拖动平移。

输出时按区域做**面积平均重采样**（缩小）或**双线性插值**（放大），
避免证件照缩小时出现摩尔纹。

### 5. 压缩：质量二分搜索（`encode_service.dart`）

给定期望体积上限，在质量 `10..96` 之间二分，每次真实编码一次 JPEG，
取「体积不超过目标」的最高质量结果。若最低质量仍然超标，返回最低质量结果并由界面明确告知用户。
抠图与压缩的耗时计算放在 `dart:isolate` 的 `Isolate.run` 中，不阻塞 UI。

> 这里刻意用 `dart:isolate` 而不是 Flutter 的 `compute()`：`lib/services/` 与 `lib/core/`
> 全部只依赖 `dart:typed_data` / `dart:math` / `dart:isolate` / `package:image`，
> 保持**纯 Dart**，因此核心算法可以用 `dart run` 直接跑起来验证，不必等模拟器。

### 6. 排版：自动挑最优网格（`layout_service.dart`）

枚举所有 `(列, 行)` 组合（`行 = ceil(张数 / 列)`），计算该组合下照片能放大的比例，
取比例最大的那个。6 寸相纸排 8 张一寸照会自动落到 **4 × 2**。

---

## 六、已知限制与可选增强

### 纯色/浅色背景粘连

洪水填充对比的是颜色。如果**人物衣物与背景颜色非常接近**（例如白衬衫 + 白墙），
两者在色距上无法区分，就会出现粘连。缓解手段：

- 把「抠图容差」调小（界面会即时重算）；
- 用「抹前景」画笔把误判的区域涂回来。

### 任意背景的精细化抠图（可选，需自行接入）

若要处理复杂背景（户外、杂乱室内），建议接入端上人像分割模型：

```bash
flutter pub add google_mlkit_selfie_segmentation
```

然后在 `SegmentationService.buildMask` 里用 ML Kit 的遮罩替换洪水填充结果——
`MaskResult` 的数据结构（`Uint8List`，0 = 前景 / 255 = 背景）与下游
`RecolorService` 完全解耦，只需替换遮罩来源，换底、压缩、排版链路都不用改。
注意该库要求 Android minSdk 21+ / iOS 15.5+，且不能在模拟器上运行。

---

## 七、依赖

| 包 | 用途 |
| --- | --- |
| `image_picker` | 相册选图 / 相机拍照 |
| `image` | 纯 Dart 图像编解码（JPEG 质量控制、PNG 编码、EXIF 方向烘焙） |
| `path_provider` | 临时目录 |
| `gal` | 保存到系统相册 + 权限处理 |
| `share_plus` | 系统分享面板 |

---

## 八、测试

```bash
flutter test                                   # 单元测试
dart run tool/verify_algorithms.dart build/verify   # 端到端跑一遍算法并导出示例图
```

### 1. 单元测试

覆盖范围：

- `test/pixel_buffer_test.dart` —— 缓冲区校验、旋转四向正确性、镜像、区域重采样（面积平均/双线性）、越界贴图
- `test/pipeline_test.dart` —— 规格像素换算、背景主色估计、洪泛掩膜（含「肩膀延伸到底边不被吃掉」的回归用例）、
  画笔修补越界安全、换底色（纯色/渐变/透明/去色溢）、压缩（二分命中目标体积）、排版网格

### 2. 无设备算法验证（`tool/verify_algorithms.dart`）

不依赖 Flutter，用 `dart run` 直接执行。它会合成一张「蓝底 + 人像」的假证件照，
把「抠图 → 换底色 → 压缩 → 排版」整条链路真实跑一遍，输出 **56 项断言**和一组 PNG 供肉眼检查：

| 输出文件 | 内容 |
| --- | --- |
| `00_source.png` | 合成的原图（蓝底） |
| `01_white.png` / `02_red.png` / `03_gradient.png` / `04_transparent.png` | 四种底色成片 |
| `01b_edge_a_raw.png` / `01c_edge_b_decon_only.png` | 边缘处理对照片（不做反解 / 只做反解不投影） |
| `01d_zoom_*.png` | 头部边缘 **8 倍最近邻放大**，用于检查有没有彩边 |
| `05_output.png` | 最终 PNG 成片 |
| `06_sheet_6inch_8.png` / `07_sheet_a4_12.png` | 6 寸、A4 排版稿 |

脚本还会打印过渡带的平均蓝偏量，便于量化对比三种边缘策略：

```
[INFO] 过渡带平均蓝偏量（0 最中性，正=残留蓝边，负=偏暖）:
       A 什么都不做 = 0
       B 仅去色溢   = -17
       C 颜色投影   = -12
```

> 注意：这个数字只看**绝对偏色量**才有意义，它不区分「正确的前景到白底的渐变」和「彩边」。
> 真正的判据是 `01d_zoom_*` 那三张放大图——A 有蓝色描边，B 有紫灰/黄色彩边，C 干净。
