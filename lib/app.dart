import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'ui/pages/home_page.dart';

class IdPhotoApp extends StatelessWidget {
  const IdPhotoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '证件照',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const HomePage(),
      builder: (BuildContext context, Widget? child) {
        // 锁定文字缩放，避免系统大字体把工具面板挤变形
        final MediaQueryData data = MediaQuery.of(context);
        return MediaQuery(
          data: data.copyWith(
            textScaler: TextScaler.linear(
              data.textScaler.scale(1).clamp(0.9, 1.15),
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
