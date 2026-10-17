import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'screens/role_picker_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SmartOrderApp());
}

/// Ứng dụng Quản lý & Gọi món Smart Order
class SmartOrderApp extends StatelessWidget {
  const SmartOrderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Order',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const RolePickerScreen(),
    );
  }
}
