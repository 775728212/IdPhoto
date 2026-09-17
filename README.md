# 证件照 App（Flutter）

一个纯本地运行的证件照**工具箱**：**裁剪大小 / 压缩大小 / 换底色 / 加水印 / 拼图排版**
五个**相互独立**的工具，想用哪个点哪个 —— 只想去掉蓝底就点「换底色」，
不会被塞进一遍「必须先裁剪、再换底、最后导出」的流程里。

不依赖任何云端服务，所有图像处理都在手机上完成。

---

## 一、功能

五个独立工具（每个都是工具箱首页上的一个入口）：

| 工具 | 能力 |
| --- | --- |
| **裁剪大小** | 30+ 标准规格（一寸/二寸/小一寸/大一寸/护照/身份证/社保卡/驾驶证/结婚证/美国签证/申根签证/考研/公务员/四六级…），按 `mm ÷ 25.4 × DPI` 精确换算像素；**自定义尺寸可直接输入像素**（16 ~ 20000 px）+ 6 组常用预设（一寸 295×413、二寸 413×579、身份证 358×441…）；双指缩放、单指拖动；左右旋转 90°、水平镜像；证件照构图参考线（头顶留白 10% / 下巴 62%）与三分网格 |
| **压缩大小** | 不裁剪、不换底，直接进压缩：**按体积**（20/30/50/100/200/500 KB）**二分搜索**出画质最好的参数，或**按画质**手动拖质量条；可先**限制最长边**（1600/1200/800/600/400 px）再压缩，比死压 JPEG 画质好得多；支持 JPG / PNG，实时显示成片体积 |
| **换底色** | 基于**边界洪水填充**的自动抠图；10 种内置底色（纯白 / 标准蓝 / 深蓝 / 浅蓝 / 标准红 / 大红 / 浅灰 / 渐变蓝 / 渐变灰 / 透明）；三点精细控制（容差 / 去边缘杂色 / 边缘羽化）；吸管手动取背景色；画笔手动涂抹修补背景与前景；长按对比原图。**裁剪是可选的**——默认直接拿原图换底，想去掉多余部分再点「去裁剪」 |
| **加水印** | 自定义水印文字（支持中文）、**字号**（按图宽比例，换图大小观感一致）、**不透明度**、颜色（白/黑/红/蓝/灰）、加粗；**4 种排版**：平铺斜排（可调间距，防盗用最强）/ 居中 / 底部横条 / 右下角；长按对比原图。裁剪同样是可选的 |
| **拼图排版** | 两种玩法：**一张照片印多份**（1~16 张，5 寸 / 6 寸 / A4 横版相纸，自动挑占满程度最高的「列 × 行」）；**多张不同照片拼一张**（一次多选，每张各自裁剪后按格子等比贴图，不裁不拉，保持各自长宽比）。可调间距（0/4/8/16/24 px）与裁切线开关 |

所有工具共用的收尾环节：

| 环节 | 能力 |
| --- | --- |
| **导出** | 保存到系统相册（独立相册「证件照」）、调起系统分享面板；输出格式 JPG / PNG 可选，透明底自动锁 PNG |


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
│   │   ├── photo_specs.dart      30+ 证件照规格表（毫米 + DPI → 像素）+ PhotoSpec.custom 自定义像素规格
│   │   └── bg_swatches.dart      底色库（含渐变与透明）
│   ├── theme/app_theme.dart      浅色主题、色板、圆角规范
│   └── utils/
│       └── pixel_buffer.dart     ★ 统一像素载体 + 几何变换（旋转/镜像/区域重采样/贴图）
│
├── models/
│   ├── crop_session.dart         ★ 裁剪会话（旋转 / 镜像 / 裁剪框 / 输出尺寸），三个工具共用
│   ├── recolor_state.dart        ★ 换底色状态（掩膜 / 参数 / 合成结果）
│   └── output_options.dart       输出格式与压缩策略（含文件名派生）
│
├── services/
│   ├── photo_picker.dart         选图入口（单张 / 多选）+ 解码，统一异常与失败计数
│   ├── image_loader.dart         解码 + EXIF 方向烘焙 + 工作分辨率归一化
│   ├── segmentation_service.dart ★ 抠图（背景主色估计 / 洪水填充 / 膨胀 / 羽化 / 画笔）
│   ├── recolor_service.dart      ★ 换底色（含边缘去色溢与渐变底色）
│   ├── watermark_service.dart    ★ 加水印（Flutter canvas 渲染文字层 → 回读像素做 alpha 合成）
│   ├── encode_service.dart       编码与压缩（JPEG 质量二分搜索）
│   ├── layout_service.dart       ★ 相纸排版（单张重复 buildSheet / 多张混排 buildMixedSheet）
│   ├── export_service.dart       保存相册 / 系统分享（按平台分流 io / web）
│   └── export/                   export_stub / export_io / export_web（条件导入）
│
└── ui/
    ├── pages/
    │   ├── home_page.dart        工具箱首页：五个工具的入口
    │   └── tools/
    │       ├── crop_editor_page.dart   裁剪编辑器（含可复用的 CropHintCard）
    │       ├── recolor_editor_page.dart 换底色编辑器（裁剪可选）
    │       ├── watermark_tool_page.dart 加水印工具
    │       ├── sheet_tool_page.dart     拼图排版工具（两种模式）
    │       └── output_page.dart         统一的「预览 → 输出设置 → 保存分享」
    └── widgets/
        ├── crop_canvas.dart      裁剪手势与构图参考线
        ├── pixel_buffer_view.dart PixelBuffer → ui.Image 的带缓存预览 + 棋盘格
        ├── spec_picker_sheet.dart 全规格选择面板（含自定义像素输入）
        ├── photo_source_sheet.dart 相册 / 拍照来源面板
        ├── output_settings_card.dart 格式 + 压缩 + 尺寸上限设置卡片
        ├── save_bar.dart         保存 / 分享动作条（含 StatTile / ChoiceTile / ChipRow）
        └── common.dart           卡片 / 滑块 / 胶囊选择 / 底色选择 / 工具按钮 / 步进器 / 加载遮罩

tool/
├── verify_algorithms.dart         ★ 纯 Dart 端到端算法验证（无需设备，导出示例图）
└── patch_platforms.py             补齐 Android / iOS 权限声明（幂等）
```

### 工具化架构

原来的实现是一条固定流水线（`EditSession` + 裁剪页 → 换底页 → 导出页），
共用一份臃肿的全局状态。改成工具箱后按**每个工具只依赖自己需要的状态**重新切分：

| 状态 | 谁在用 |
| --- | --- |
| `CropSession` | 裁剪工具（主界面）、换底色 / 加水印（可选子页面）、拼图（每张照片各一份） |
| `RecolorState` | 只有换底色工具 |
| `OutputOptions` | 裁剪 / 压缩 / 换底 / 水印 / 拼图，全部在收尾时用 |

`CropSession.cropEnabled` 是这次拆分的关键开关：为 `false` 时 `baseImage` 直接返回工作图本身，
于是「换底色」「加水印」可以默认**不做裁剪**，用户想去掉多余部分时再点「去裁剪」。


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

两条路径：

- **`buildSheet`（同一张照片印多份）**——枚举所有 `(列, 行)` 组合（`行 = ceil(张数 / 列)`），
  计算该组合下照片能放大的比例，取比例最大的那个。6 寸相纸排 8 张一寸照会自动落到 **4 × 2**。
- **`buildMixedSheet`（多张不同照片拼一张）**——每张照片长宽比可以完全不同，所以不能先定一个
  「单张尺寸」再复制。改为：枚举 `(列, 行)`，把每张各自等比缩放到格子里，累计**实际落纸面积**，
  取面积最大的组合；然后逐格居中贴图。**不裁不拉**，每张保持自己的比例 ——
  拼图工具已经让用户逐张裁剪过了，这里再裁一次等于推翻用户的选择。

### 7. 加水印：canvas 渲染文字层 + 像素回读合成（`watermark_service.dart`）

这里踩了一个坑：`package:image` 自带的位图字体（`arial24` 等）**只有 ASCII**，
中文会直接画成方块，而中文恰恰是证件照水印最常用的（「仅供办理 XX 使用」）。
所以不用它，改成：

1. 建一块与照片等大的**全透明** `ui.PictureRecorder` 画布；
2. 用 Flutter 的 `TextPainter` 把水印文字画上去（这样系统字体、中文、字重全部可用）；
   平铺模式则是把画布旋转 30° 后按网格重复绘制，奇数行错开半格避免出现明显竖列空档；
3. `toImage` → `toByteData(rawRgba)` 把文字层回读成像素；
4. 用 `ImageOps.blit` 与原图做 alpha 合成。

**注意 `rawRgba` 给的是预乘 alpha 的数据**，直接当普通 RGBA 去混会偏暗（半透明浅色文字尤其明显），
所以回读后先做一次反预乘：`r = r × 255 / a`。

字号与间距都按**图宽比例**表达（`fontSize = width × ratio`），
这样同一套参数在 295px 的小图和 2400px 的原图上观感一致，用户不需要每换一张图就重调。


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
- `test/pipeline_test.dart` —— 规格像素换算、**自定义像素规格**（像素优先、夹紧、毫米标签格式）、
  背景主色估计、洪泛掩膜（含「肩膀延伸到底边不被吃掉」的回归用例）、画笔修补越界安全、
  换底色（纯色/渐变/透明/去色溢）、压缩（二分命中目标体积）、
  排版网格（单张重复 + **多张不同比例混排**：排得下 / 不拉伸 / 空列表安全）

### 2. 无设备算法验证（`tool/verify_algorithms.dart`）

不依赖 Flutter，用 `dart run` 直接执行。它会合成一张「蓝底 + 人像」的假证件照，
把「抠图 → 换底色 → 压缩 → 排版 → 多张混排」整条链路真实跑一遍，
输出 **64 项断言**和一组 PNG 供肉眼检查：

| 输出文件 | 内容 |
| --- | --- |
| `00_source.png` | 合成的原图（蓝底） |
| `01_white.png` / `02_red.png` / `03_gradient.png` / `04_transparent.png` | 四种底色成片 |
| `01b_edge_a_raw.png` / `01c_edge_b_decon_only.png` | 边缘处理对照片（不做反解 / 只做反解不投影） |
| `01d_zoom_*.png` | 头部边缘 **8 倍最近邻放大**，用于检查有没有彩边 |
| `05_output.png` | 最终 PNG 成片 |
| `06_sheet_6inch_8.png` / `07_sheet_a4_12.png` | 6 寸、A4 排版稿（同张重复） |
| `08_sheet_mixed_4.png` | 4 张**不同长宽比**照片拼一张的混排稿 |

脚本还会打印过渡带的平均蓝偏量，便于量化对比三种边缘策略：

```
[INFO] 过渡带平均蓝偏量（0 最中性，正=残留蓝边，负=偏暖）:
       A 什么都不做 = 0
       B 仅去色溢   = -17
       C 颜色投影   = -12
```

> 注意：这个数字只看**绝对偏色量**才有意义，它不区分「正确的前景到白底的渐变」和「彩边」。
> 真正的判据是 `01d_zoom_*` 那三张放大图——A 有蓝色描边，B 有紫灰/黄色彩边，C 干净。
