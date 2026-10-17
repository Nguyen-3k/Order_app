import 'package:flutter/material.dart';

/// Bảng màu dùng chung cho toàn bộ dự án Smart Order
class AppColors {
  // Màu chủ đạo
  static const Color primary = Color(0xFFFF6B00); // Cam ấm hiện đại của F&B
  static const Color primaryLight = Color(0xFFFF8E3C);
  static const Color primaryDark = Color(0xFFD65800);

  // Nền & bề mặt
  static const Color background = Color(0xFFF8F9FA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF1F3F5);

  // Chữ & Đường viền
  static const Color textPrimary = Color(0xFF212529);
  static const Color textSecondary = Color(0xFF6C757D);
  static const Color border = Color(0xFFE9ECEF);

  // Màu sắc đại diện cho 4 vai trò (giúp nhận diện ngay lập tức khi demo)
  static const Color roleAdmin = Color(0xFF3F51B5);     // Xanh tím Indigo - Quản trị
  static const Color roleStaff = Color(0xFFFF6B00);     // Cam - Phục vụ năng động
  static const Color roleKitchen = Color(0xFFD32F2F);   // Đỏ - Nhà bếp
  static const Color roleBar = Color(0xFF00897B);       // Xanh ngọc lục bảo - Quầy Bar

  // Màu sắc trạng thái bàn
  static const Color tableAvailable = Color(0xFF2E7D32); // Xanh lá - Bàn trống
  static const Color tableOccupied = Color(0xFFD32F2F);  // Đỏ - Có khách
  static const Color tableReserved = Color(0xFFF57C00);  // Cam - Đã đặt / Chờ thanh toán

  // Màu sắc trạng thái đơn hàng / món
  static const Color statusPending = Color(0xFFFFA000);   // Vàng cam - Chờ xử lý
  static const Color statusPreparing = Color(0xFF1976D2); // Xanh dương - Đang chế biến
  static const Color statusReady = Color(0xFF388E3C);     // Xanh lá - Đã xong / Chờ bưng
  static const Color statusCompleted = Color(0xFF616161); // Xám - Đã hoàn tất
}

