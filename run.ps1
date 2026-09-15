# 证件照 App —— 一键初始化并运行
#
# 用法（在项目根目录）：
#   powershell -ExecutionPolicy Bypass -File .\run.ps1            # 初始化 + 调试运行
#   powershell -ExecutionPolicy Bypass -File .\run.ps1 -BuildApk  # 只出 Android release 包
#   powershell -ExecutionPolicy Bypass -File .\run.ps1 -SetupOnly # 只做初始化，不运行
#
# 说明：脚本兼容 Windows PowerShell 5.1（不使用 && / ?? 等 PS7 语法）。

param(
    [switch]$SetupOnly,
    [switch]$BuildApk
)

$ErrorActionPreference = 'Stop'
Set-Location -Path $PSScriptRoot

function Write-Step([string]$text) {
    Write-Host ""
    Write-Host "==> $text" -ForegroundColor Cyan
}

function Assert-ExitCode([string]$what) {
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[失败] $what（退出码 $LASTEXITCODE）" -ForegroundColor Red
        exit $LASTEXITCODE
    }
}

# ---------------------------------------------------------------- 1. 检查环境
Write-Step '检查 Flutter 环境'
$flutter = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutter) {
    Write-Host '[失败] PATH 中找不到 flutter 命令。请先安装 Flutter SDK 3.38.1+ 并加入 PATH。' -ForegroundColor Red
    Write-Host '        下载地址：https://docs.flutter.dev/get-started/install/windows' -ForegroundColor Yellow
    exit 1
}
flutter --version
Assert-ExitCode 'flutter --version'

# ---------------------------------------------------------------- 1.5 清理陈旧的缓存锁
# 症状：flutter 命令卡死且零输出（看起来像在下载或检查版本，其实不是）。
# 原因：上一次 flutter 进程被强杀（Ctrl+C、任务管理器结束）后留下的排他锁
#       <flutter>\bin\cache\lockfile 会让后续每一次 flutter 启动都永久阻塞。
# 处理：只在锁文件明显陈旧（超过 10 分钟没更新）时才删，避免误伤正在运行的 flutter。
$flutterRoot = Split-Path (Split-Path $flutter.Source -Parent) -Parent
$lockFile = Join-Path $flutterRoot 'bin\cache\lockfile'
if (Test-Path $lockFile) {
    $ageMinutes = ((Get-Date) - (Get-Item $lockFile).LastWriteTime).TotalMinutes
    if ($ageMinutes -gt 10) {
        Write-Host ('[清理] flutter 缓存锁已陈旧 {0:N0} 分钟，删除它以免后续命令卡死' -f $ageMinutes) -ForegroundColor Yellow
        Remove-Item $lockFile -Force
    }
}

# ---------------------------------------------------------------- 2. 生成平台目录
if (-not (Test-Path 'android') -or -not (Test-Path 'ios')) {
    Write-Step '生成 android / ios 平台目录'
    flutter create --platforms=android,ios --org com.idphoto --project-name id_photo_maker .
    Assert-ExitCode 'flutter create'
} else {
    Write-Host 'android / ios 目录已存在，跳过 flutter create' -ForegroundColor DarkGray
}

# ---------------------------------------------------------------- 3. 依赖
Write-Step '拉取依赖'
flutter pub get
Assert-ExitCode 'flutter pub get'

# ---------------------------------------------------------------- 4. 平台权限
Write-Step '写入相册 / 相机权限声明'
$python = Get-Command python -ErrorAction SilentlyContinue
if ($python) {
    python tool\patch_platforms.py
} else {
    Write-Host '[跳过] 未找到 python，请参考 README.md 第三节手动写入权限。' -ForegroundColor Yellow
}

# ---------------------------------------------------------------- 5. 收尾
if ($BuildApk) {
    Write-Step '构建 Android release APK'
    flutter build apk --release
    Assert-ExitCode 'flutter build apk'
    Write-Host ""
    Write-Host '产物：build\app\outputs\flutter-apk\app-release.apk' -ForegroundColor Green
    exit 0
}

if ($SetupOnly) {
    Write-Host ""
    Write-Host '初始化完成。运行 `flutter run` 启动应用。' -ForegroundColor Green
    exit 0
}

Write-Step '启动应用（选择已连接的设备）'
flutter devices
flutter run
