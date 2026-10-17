import 'package:flutter/material.dart';

/// Tiện ích hiển thị thông báo hệ thống và phản hồi người dùng
class AppFeedback {
  /// Hiển thị thông báo tính năng đang phát triển
  static void showFeatureUnderDevelopment(BuildContext context, [String? featureName]) {
    final message = featureName != null
        ? 'Chức năng "$featureName" sẽ được phát triển ở giai đoạn tiếp theo.'
        : 'Chức năng sẽ được phát triển ở giai đoạn tiếp theo.';

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info_outline_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontSize: 14, color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF2C3E50),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

