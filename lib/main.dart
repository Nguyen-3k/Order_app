
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/supabase_test.dart';
import 'core/theme/app_theme.dart';
import 'screens/role_picker_screen.dart';
import 'supabase_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SupabaseConfig.initialize();

  await testSupabaseConnection();
  
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