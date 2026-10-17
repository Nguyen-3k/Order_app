import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';

/// AppBar chuẩn có hiển thị vai trò hiện tại và nút quay lại / đổi vai trò nhanh
class RoleHeaderAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String roleName;
  final Color roleColor;
  final IconData roleIcon;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;

  const RoleHeaderAppBar({
    super.key,
    required this.title,
    required this.roleName,
    required this.roleColor,
    required this.roleIcon,
    this.actions,
    this.bottom,
  });

  @override
  Size get preferredSize => Size.fromHeight(
        kToolbarHeight + (bottom?.preferredSize.height ?? 0.0),
      );

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: roleColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: roleColor.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(roleIcon, size: 16, color: roleColor),
                const SizedBox(width: 6),
                Text(
                  roleName,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: roleColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ],
      ),
      actions: [
        ...?actions,
        TextButton.icon(
          onPressed: () {
            // Quay về màn hình chọn vai trò
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
          icon: const Icon(Icons.swap_horiz_rounded, size: 18),
          label: const Text('Đổi vai trò'),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.textSecondary,
          ),
        ),
        const SizedBox(width: 8),
      ],
      bottom: bottom,
    );
  }
}
