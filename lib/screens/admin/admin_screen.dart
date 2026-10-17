import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/app_feedback.dart';
import '../../widgets/role_header_app_bar.dart';

/// Màn hình Quản trị viên (Admin)
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: RoleHeaderAppBar(
        title: 'Bảng Quản Trị',
        roleName: 'Admin',
        roleColor: AppColors.roleAdmin,
        roleIcon: Icons.admin_panel_settings_rounded,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.roleAdmin,
          labelColor: AppColors.roleAdmin,
          unselectedLabelColor: AppColors.textSecondary,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          tabs: const [
            Tab(icon: Icon(Icons.dashboard_outlined, size: 20), text: 'Tổng quan'),
            Tab(icon: Icon(Icons.restaurant_menu_outlined, size: 20), text: 'Quản lý món'),
            Tab(icon: Icon(Icons.table_restaurant_outlined, size: 20), text: 'Quản lý bàn'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildDashboardTab(),
          _buildMenuManagementTab(),
          _buildTableManagementTab(),
        ],
      ),
    );
  }

  /// Tab 1: Tổng quan (Dashboard)
  Widget _buildDashboardTab() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth > 800;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Banner thông báo demo
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.roleAdmin.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.roleAdmin.withValues(alpha: 0.2)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: AppColors.roleAdmin, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Dữ liệu thống kê bên dưới là dữ liệu mô phỏng khung giao diện demo. Hệ thống chưa kết nối cơ sở dữ liệu thật.',
                        style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              const Text(
                'Chỉ số hoạt động trong ngày',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 12),

              // Lưới thẻ KPI thống kê
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: isWide ? 4 : 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: isWide ? 1.7 : 1.35,
                children: [
                  _buildStatCard('Bàn đang phục vụ', '8 / 12', Icons.table_restaurant_rounded, Colors.orange),
                  _buildStatCard('Đơn hàng hôm nay', '24 đơn', Icons.receipt_long_rounded, Colors.blue),
                  _buildStatCard('Doanh thu tạm tính', '4.250.000 đ', Icons.payments_rounded, Colors.green),
                  _buildStatCard('Món đang chờ nấu/pha', '5 món', Icons.pending_actions_rounded, Colors.red),
                ],
              ),

              const SizedBox(height: 28),
              const Text(
                'Top món gọi nhiều hôm nay',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 12),

              Card(
                child: ListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _buildPopularItemTile('1', 'Bò lúc lắc khoai tây', 'Món ăn', '18 phần', '125.000 đ'),
                    const Divider(),
                    _buildPopularItemTile('2', 'Trà đào cam sả', 'Đồ uống', '15 ly', '35.000 đ'),
                    const Divider(),
                    _buildPopularItemTile('3', 'Cơm chiên hải sản', 'Món ăn', '12 dĩa', '85.000 đ'),
                    const Divider(),
                    _buildPopularItemTile('4', 'Cà phê muối', 'Đồ uống', '10 ly', '28.000 đ'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
              ],
            ),
            Text(
              value,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPopularItemTile(String rank, String name, String category, String count, String price) {
    return ListTile(
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: AppColors.surfaceVariant,
        child: Text(rank, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
      ),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text('$category • $price', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          count,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.primary),
        ),
      ),
    );
  }

  /// Tab 2: Quản lý thực đơn
  Widget _buildMenuManagementTab() {
    final sampleItems = [
      {'name': 'Cơm sườn nướng mật ong', 'type': 'Món ăn (Bếp)', 'price': '65.000 đ', 'isAvailable': true},
      {'name': 'Bò lúc lắc khoai tây', 'type': 'Món ăn (Bếp)', 'price': '125.000 đ', 'isAvailable': true},
      {'name': 'Mì xào hải sản', 'type': 'Món ăn (Bếp)', 'price': '75.000 đ', 'isAvailable': true},
      {'name': 'Lẩu Thái hải sản', 'type': 'Món ăn (Bếp)', 'price': '220.000 đ', 'isAvailable': false},
      {'name': 'Trà đào cam sả', 'type': 'Đồ uống (Bar)', 'price': '35.000 đ', 'isAvailable': true},
      {'name': 'Cà phê muối', 'type': 'Đồ uống (Bar)', 'price': '28.000 đ', 'isAvailable': true},
      {'name': 'Sinh tố bơ sầu riêng', 'type': 'Đồ uống (Bar)', 'price': '45.000 đ', 'isAvailable': true},
    ];

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(
                          hintText: 'Tìm kiếm món ăn, đồ uống...',
                          prefixIcon: Icon(Icons.search, size: 20),
                          isDense: true,
                        ),
                        onChanged: (val) {
                          // Search khung demo
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.roleAdmin),
                      onPressed: () => AppFeedback.showFeatureUnderDevelopment(context, 'Thêm món mới vào thực đơn'),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Thêm món'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: sampleItems.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = sampleItems[index];
                    final isAvailable = item['isAvailable'] as bool;
                    final isBar = (item['type'] as String).contains('Bar');

                    return Card(
                      child: ListTile(
                        leading: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: isBar ? AppColors.roleBar.withValues(alpha: 0.1) : AppColors.roleKitchen.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            isBar ? Icons.local_bar_rounded : Icons.soup_kitchen_rounded,
                            color: isBar ? AppColors.roleBar : AppColors.roleKitchen,
                          ),
                        ),
                        title: Text(item['name'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('${item['type']} • ${item['price']}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isAvailable ? Colors.green.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                isAvailable ? 'Còn hàng' : 'Hết hàng',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: isAvailable ? Colors.green : Colors.red,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 20),
                              tooltip: 'Chỉnh sửa',
                              onPressed: () => AppFeedback.showFeatureUnderDevelopment(context, 'Chỉnh sửa thông tin món'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Tab 3: Quản lý bàn
  Widget _buildTableManagementTab() {
    final tables = List.generate(
      12,
      (index) => {
        'name': 'Bàn ${(index + 1).toString().padLeft(2, '0')}',
        'area': index < 6 ? 'Tầng 1 (Máy lạnh)' : 'Tầng 2 (Sân thượng)',
        'seats': index % 2 == 0 ? 4 : 6,
      },
    );

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Danh sách cấu hình bàn (12 bàn)',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.roleAdmin),
                      onPressed: () => AppFeedback.showFeatureUnderDevelopment(context, 'Thêm cấu hình bàn mới'),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Thêm bàn'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: tables.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final table = tables[index];
                    return Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: AppColors.surfaceVariant,
                          child: Icon(Icons.table_restaurant_outlined, color: AppColors.roleAdmin),
                        ),
                        title: Text(table['name'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('Khu vực: ${table['area']} • Sức chứa: ${table['seats']} người'),
                        trailing: IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          tooltip: 'Chỉnh sửa bàn',
                          onPressed: () => AppFeedback.showFeatureUnderDevelopment(context, 'Chỉnh sửa thông tin bàn'),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
