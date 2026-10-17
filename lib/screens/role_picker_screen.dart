import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import 'admin/admin_screen.dart';
import 'staff/staff_screen.dart';
import 'kitchen/kitchen_screen.dart';
import 'bar/bar_screen.dart';

/// Màn hình chọn vai trò demo chính của ứng dụng Smart Order
class RolePickerScreen extends StatelessWidget {
  const RolePickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth > 700;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Logo & Tiêu đề
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.restaurant_rounded,
                      size: 40,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Smart Order',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Hệ thống Quản lý và Gọi món Thông minh cho Nhà hàng / Quán Cafe',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Tag định hướng phiên bản
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.dashboard_customize_rounded, size: 16, color: AppColors.primary),
                        SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Giai đoạn B: Nền tảng giao diện & Điều hướng demo 4 phân hệ',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 36),

                  // Lời nhắc chọn vai trò
                  Align(
                    alignment: isWide ? Alignment.centerLeft : Alignment.center,
                    child: const Text(
                      'Vui lòng chọn vai trò để trải nghiệm:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Lưới 4 vai trò thích ứng bằng Wrap và LayoutBuilder (chống tràn pixel)
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isTwoColumn = constraints.maxWidth > 650;
                      final cardWidth = isTwoColumn
                          ? (constraints.maxWidth - 16) / 2
                          : constraints.maxWidth;

                      return Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: [
                          _buildRoleCard(
                            context: context,
                            width: cardWidth,
                            title: 'Quản trị viên (Admin)',
                            subtitle: 'Quản lý thực đơn món, sơ đồ bàn và theo dõi tổng quan',
                            icon: Icons.admin_panel_settings_rounded,
                            badgeText: 'Toàn quyền',
                            themeColor: AppColors.roleAdmin,
                            features: ['Tổng quan doanh thu', 'Quản lý món', 'Quản lý bàn'],
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const AdminScreen()),
                              );
                            },
                          ),
                          _buildRoleCard(
                            context: context,
                            width: cardWidth,
                            title: 'Nhân viên phục vụ (Staff)',
                            subtitle: 'Xem sơ đồ trạng thái bàn, mở bàn và lên đơn gọi món cho khách',
                            icon: Icons.room_service_rounded,
                            badgeText: 'Tại bàn',
                            themeColor: AppColors.roleStaff,
                            features: ['Sơ đồ bàn trực quan', 'Lên order nhanh', 'Gửi bếp & bar'],
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const StaffScreen()),
                              );
                            },
                          ),
                          _buildRoleCard(
                            context: context,
                            width: cardWidth,
                            title: 'Nhà bếp (Kitchen - KDS)',
                            subtitle: 'Màn hình KDS hiển thị các món ăn cần chế biến theo thứ tự',
                            icon: Icons.soup_kitchen_rounded,
                            badgeText: 'Món ăn',
                            themeColor: AppColors.roleKitchen,
                            features: ['Hàng đợi món ăn', 'Chờ nấu → Đang nấu', 'Báo hoàn thành'],
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const KitchenScreen()),
                              );
                            },
                          ),
                          _buildRoleCard(
                            context: context,
                            width: cardWidth,
                            title: 'Quầy pha chế (Bar - BDS)',
                            subtitle: 'Màn hình hiển thị danh sách đồ uống cần pha chế riêng biệt',
                            icon: Icons.local_bar_rounded,
                            badgeText: 'Đồ uống',
                            themeColor: AppColors.roleBar,
                            features: ['Hàng đợi thức uống', 'Ghi chú đường/đá', 'Pha chế nhanh'],
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const BarScreen()),
                              );
                            },
                          ),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 32),
                  // Chú thích chân trang
                  const Text(
                    '💡 Mẹo demo: Bạn có thể nhấn nút "Đổi vai trò" ở góc trên bên phải bất cứ lúc nào để chuyển đổi qua lại giữa các phân hệ.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary, fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoleCard({
    required BuildContext context,
    required double width,
    required String title,
    required String subtitle,
    required IconData icon,
    required String badgeText,
    required Color themeColor,
    required List<String> features,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: width,
      child: Card(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          splashColor: themeColor.withValues(alpha: 0.1),
          hoverColor: themeColor.withValues(alpha: 0.05),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: themeColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: themeColor, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: themeColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  badgeText,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: themeColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.3),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: features.map((feat) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '• $feat',
                        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
