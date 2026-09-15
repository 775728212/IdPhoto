#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""为证件照 App 补齐 Android / iOS 的平台权限配置。

用法（在项目根目录执行，需先跑过 `flutter create .`）：

    python tool/patch_platforms.py

脚本是**幂等**的：重复执行不会写入重复条目。
支持 Flutter 3.16+ 的 Kotlin DSL（build.gradle.kts）与 Groovy DSL（build.gradle）。
"""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

ANDROID_MANIFEST = ROOT / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
ANDROID_GRADLE_KTS = ROOT / "android" / "app" / "build.gradle.kts"
ANDROID_GRADLE_GROOVY = ROOT / "android" / "app" / "build.gradle"
IOS_INFO_PLIST = ROOT / "ios" / "Runner" / "Info.plist"
MACOS_INFO_PLIST = ROOT / "macos" / "Runner" / "Info.plist"

PERM_STORAGE = (
    '    <!-- gal: 保存到相册（API <= 29 需要写外部存储权限） -->\n'
    '    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"\n'
    '        android:maxSdkVersion="29" />\n'
)

IOS_KEYS = [
    ("NSPhotoLibraryAddUsageDescription", "需要保存制作好的证件照到你的相册"),
    ("NSPhotoLibraryUsageDescription", "需要读取相册中的照片来制作证件照"),
    ("NSCameraUsageDescription", "需要使用相机拍摄证件照"),
]


def log(msg: str) -> None:
    print(f"  {msg}")


def patch_android_manifest() -> bool:
    if not ANDROID_MANIFEST.exists():
        log(f"跳过：未找到 {ANDROID_MANIFEST.relative_to(ROOT)}")
        return False

    text = ANDROID_MANIFEST.read_text(encoding="utf-8")
    original = text

    if "android.permission.WRITE_EXTERNAL_STORAGE" not in text:
        # 插到 <application 之前；找不到就插到 <manifest ...> 之后
        app_idx = text.find("<application")
        if app_idx == -1:
            log("警告：AndroidManifest.xml 里找不到 <application> 标签")
            return False
        text = text[:app_idx] + PERM_STORAGE + "\n" + text[app_idx:]
        log("已添加 WRITE_EXTERNAL_STORAGE 权限")

    if 'android:requestLegacyExternalStorage="true"' not in text:
        text = re.sub(
            r"<application(\s)",
            '<application\n        android:requestLegacyExternalStorage="true"\\1',
            text,
            count=1,
        )
        if 'requestLegacyExternalStorage' in text:
            log("已为 <application> 添加 requestLegacyExternalStorage")
        else:
            log("警告：未能写入 requestLegacyExternalStorage，请手动确认")

    if text != original:
        ANDROID_MANIFEST.write_text(text, encoding="utf-8")
        return True
    log("AndroidManifest.xml 已经配置过")
    return False


def patch_android_gradle() -> bool:
    target = None
    if ANDROID_GRADLE_KTS.exists():
        target = ANDROID_GRADLE_KTS
        pattern = re.compile(r"minSdk\s*=\s*([^\s\)]+)")
        replacement = "minSdk = 24"
    elif ANDROID_GRADLE_GROOVY.exists():
        target = ANDROID_GRADLE_GROOVY
        pattern = re.compile(r"minSdk(?:Version)?\s*([^\s\)]+)")
        replacement = "minSdkVersion 24"
    else:
        log("跳过：未找到 app 级 build.gradle(.kts)")
        return False

    text = target.read_text(encoding="utf-8")
    if "24" in (pattern.search(text).group(1) if pattern.search(text) else ""):
        log(f"{target.name} 的 minSdk 已经是 24+")
        return False

    new_text, count = pattern.subn(replacement, text, count=1)
    if count == 0:
        log(f"警告：{target.name} 中找不到 minSdk 声明（image_picker 要求 24+）")
        return False

    target.write_text(new_text, encoding="utf-8")
    log(f"{target.name}: minSdk 已设为 24（image_picker 要求）")
    return True


def patch_plist(path: Path, label: str) -> bool:
    if not path.exists():
        log(f"跳过：未找到 {label}")
        return False

    text = path.read_text(encoding="utf-8")
    additions = [k for k, _ in IOS_KEYS if f"<key>{k}</key>" not in text]
    if not additions:
        log(f"{label} 已经配置过")
        return False

    block = "".join(
        f"\t<key>{k}</key>\n\t<string>{v}</string>\n"
        for k, v in IOS_KEYS
        if k in additions
    )
    idx = text.rfind("</dict>")
    if idx == -1:
        log(f"警告：{label} 结构异常，找不到 </dict>")
        return False

    text = text[:idx] + block + text[idx:]
    path.write_text(text, encoding="utf-8")
    log(f"{label}: 已写入 {', '.join(k.replace('NS', '').replace('UsageDescription', '') for k in additions)}")
    return True


def main() -> int:
    print("配置 Android ...")
    changed_a = patch_android_manifest()
    changed_b = patch_android_gradle()

    print("配置 iOS / macOS ...")
    changed_c = patch_plist(IOS_INFO_PLIST, "ios/Runner/Info.plist")
    changed_d = patch_plist(MACOS_INFO_PLIST, "macos/Runner/Info.plist")

    if not any([changed_a, changed_b, changed_c, changed_d]):
        print("\n无需改动，平台配置已是最新。")
    else:
        print("\n平台配置已更新。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
