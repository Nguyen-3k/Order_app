import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../widgets/order_confirm_dialog.dart';
import '../../widgets/role_header_app_bar.dart';

/// Dữ liệu món ăn trong giỏ hàng
class CartItemData {
  final String name;
  final int price;
  final String type;
  final IconData icon;
  int qty;
  String note;

  CartItemData({
    required this.name,
    required this.price,
    required this.type,
    required this.icon,
    this.qty = 1,
    this.note = '',
  });

  int get subtotal => price * qty;
}

/// Màn hình Nhân viên phục vụ (Staff)
class StaffScreen extends StatefulWidget {
  const StaffScreen({super.key});

  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedTable = 'Bàn 01';
  String _tableFilter = 'Tất cả';

  // Dữ liệu mô phỏng trạng thái 12 bàn
  final List<Map<String, dynamic>> _tables = [
    {'id': 'Bàn 01', 'status': 'available', 'seats': 4, 'time': ''},
    {'id': 'Bàn 02', 'status': 'occupied', 'seats': 4, 'time': '35 phút', 'total': '210.000 đ'},
    {'id': 'Bàn 03', 'status': 'available', 'seats': 2, 'time': ''},
    {'id': 'Bàn 04', 'status': 'occupied', 'seats': 6, 'time': '15 phút', 'total': '345.000 đ'},
    {'id': 'Bàn 05', 'status': 'reserved', 'seats': 4, 'time': 'Chờ bill', 'total': '180.000 đ'},
    {'id': 'Bàn 06', 'status': 'available', 'seats': 8, 'time': ''},
    {'id': 'Bàn 07', 'status': 'occupied', 'seats': 4, 'time': '50 phút', 'total': '450.000 đ'},
    {'id': 'Bàn 08', 'status': 'available', 'seats': 4, 'time': ''},
    {'id': 'Bàn 09', 'status': 'available', 'seats': 2, 'time': ''},
    {'id': 'Bàn 10', 'status': 'occupied', 'seats': 6, 'time': '20 phút', 'total': '290.000 đ'},
    {'id': 'Bàn 11', 'status': 'available', 'seats': 4, 'time': ''},
    {'id': 'Bàn 12', 'status': 'available', 'seats': 4, 'time': ''},
  ];

  // Danh mục thực đơn chuẩn F&B
  final List<Map<String, dynamic>> _menuItems = [
    {'name': 'Bò lúc lắc khoai tây', 'price': 125000, 'type': 'Bếp', 'icon': Icons.soup_kitchen_rounded},
    {'name': 'Cơm sườn nướng', 'price': 65000, 'type': 'Bếp', 'icon': Icons.soup_kitchen_rounded},
    {'name': 'Mì xào hải sản', 'price': 75000, 'type': 'Bếp', 'icon': Icons.soup_kitchen_rounded},
    {'name': 'Lẩu Thái hải sản', 'price': 220000, 'type': 'Bếp', 'icon': Icons.soup_kitchen_rounded},
    {'name': 'Trà đào cam sả', 'price': 35000, 'type': 'Bar', 'icon': Icons.local_bar_rounded},
    {'name': 'Cà phê muối', 'price': 28000, 'type': 'Bar', 'icon': Icons.local_bar_rounded},
    {'name': 'Sinh tố bơ sầu riêng', 'price': 45000, 'type': 'Bar', 'icon': Icons.local_bar_rounded},
    {'name': 'Nước ngọt Coca/Pepsi', 'price': 18000, 'type': 'Bar', 'icon': Icons.local_bar_rounded},
  ];

  // Giỏ hàng đồng bộ duy nhất
  final Map<String, CartItemData> _cart = {
    'Bò lúc lắc khoai tây': CartItemData(
      name: 'Bò lúc lắc khoai tây',
      price: 125000,
      type: 'Bếp',
      icon: Icons.soup_kitchen_rounded,
      qty: 1,
      note: 'Ít tiêu',
    ),
    'Trà đào cam sả': CartItemData(
      name: 'Trà đào cam sả',
      price: 35000,
      type: 'Bar',
      icon: Icons.local_bar_rounded,
      qty: 2,
      note: 'Ít ngọt, nhiều đá',
    ),
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  int get _totalAmount => _cart.values.fold(0, (sum, it) => sum + it.subtotal);
  int get _totalItemsCount => _cart.values.fold(0, (sum, it) => sum + it.qty);

  String _formatMoney(int amount) {
    return '${amount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')} đ';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: RoleHeaderAppBar(
        title: 'Nhân Viên Phục Vụ',
        roleName: 'Phục vụ',
        roleColor: AppColors.roleStaff,
        roleIcon: Icons.room_service_rounded,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.roleStaff,
          labelColor: AppColors.roleStaff,
          unselectedLabelColor: AppColors.textSecondary,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          tabs: const [
            Tab(icon: Icon(Icons.grid_view_rounded, size: 20), text: 'Sơ đồ bàn'),
            Tab(icon: Icon(Icons.add_shopping_cart_rounded, size: 20), text: 'Tạo Order'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTableMapTab(),
          _buildCreateOrderTab(),
        ],
      ),
    );
  }

  /// Tab 1: Sơ đồ bàn
  Widget _buildTableMapTab() {
    final filteredTables = _tables.where((table) {
      if (_tableFilter == 'Bàn trống') return table['status'] == 'available';
      if (_tableFilter == 'Có khách') return table['status'] == 'occupied';
      if (_tableFilter == 'Chờ thanh toán') return table['status'] == 'reserved';
      return true;
    }).toList();

    return Column(
      children: [
        // Thanh bộ lọc & Chú thích trạng thái
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: AppColors.surface,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('Tất cả'),
                const SizedBox(width: 8),
                _buildFilterChip('Bàn trống'),
                const SizedBox(width: 8),
                _buildFilterChip('Có khách'),
                const SizedBox(width: 8),
                _buildFilterChip('Chờ thanh toán'),
              ],
            ),
          ),
        ),
        const Divider(),

        // Lưới bàn
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: GridView.builder(
                  itemCount: filteredTables.length,
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 1.15,
                  ),
                  itemBuilder: (context, index) {
                    final table = filteredTables[index];
                    final status = table['status'] as String;
                    final isAvailable = status == 'available';
                    final isOccupied = status == 'occupied';

                    Color statusColor = AppColors.tableAvailable;
                    String statusLabel = 'Bàn trống';
                    if (isOccupied) {
                      statusColor = AppColors.tableOccupied;
                      statusLabel = 'Có khách';
                    } else if (status == 'reserved') {
                      statusColor = AppColors.tableReserved;
                      statusLabel = 'Chờ bill';
                    }

                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: statusColor.withValues(alpha: 0.5), width: 1.5),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          if (isAvailable) {
                            setState(() {
                              _selectedTable = table['id'] as String;
                            });
                            _tabController.animateTo(1);
                          } else {
                            _showTableDetailDialog(table);
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Flexible(
                                    child: Text(
                                      table['id'] as String,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: statusColor.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      statusLabel,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: statusColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  const Icon(Icons.people_alt_outlined, size: 14, color: AppColors.textSecondary),
                                  const SizedBox(width: 4),
                                  Text('${table['seats']} chỗ', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                ],
                              ),
                              if (!isAvailable && (table['time'] as String).isNotEmpty)
                                Text(
                                  '⏱ ${table['time']} • ${table['total']}',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                                )
                              else
                                const Text(
                                  '👉 Nhấn để mở bàn',
                                  style: TextStyle(fontSize: 11, color: AppColors.tableAvailable, fontWeight: FontWeight.w500),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label) {
    final isSelected = _tableFilter == label;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) setState(() => _tableFilter = label);
      },
      selectedColor: AppColors.roleStaff.withValues(alpha: 0.15),
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? AppColors.roleStaff : AppColors.textPrimary,
      ),
    );
  }

  void _showTableDetailDialog(Map<String, dynamic> table) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.table_restaurant, color: AppColors.roleStaff),
            const SizedBox(width: 8),
            Text('Chi tiết ${table['id']}'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Thời gian ngồi: ${table['time']}'),
            const SizedBox(height: 4),
            Text('Tổng tiền tạm tính: ${table['total']}', style: const TextStyle(fontWeight: FontWeight.bold)),
            const Divider(height: 20),
            const Text('Các món đang phục vụ (Demo):', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            const Text('• 1x Bò lúc lắc khoai tây (Đã ra món)'),
            const Text('• 2x Trà đào cam sả (Đã ra món)'),
            const Text('• 1x Cơm chiên hải sản (Đang nấu)'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Đóng'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.roleStaff),
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _selectedTable = table['id'] as String);
              _tabController.animateTo(1);
            },
            child: const Text('Gọi thêm món'),
          ),
        ],
      ),
    );
  }

  /// Tab 2: Tạo order
  Widget _buildCreateOrderTab() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth > 800;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: isWide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: _buildMenuList()),
                  const VerticalDivider(),
                  Expanded(flex: 2, child: _buildCartPanel()),
                ],
              )
            : Column(
                children: [
                  Expanded(child: _buildMenuList()),
                  const Divider(),
                  _buildCartBottomBar(),
                ],
              ),
      ),
    );
  }

  Widget _buildMenuList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Chọn bàn
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: AppColors.surface,
          child: Row(
            children: [
              const Text('Đang tạo đơn cho: ', style: TextStyle(fontWeight: FontWeight.w600)),
              DropdownButton<String>(
                value: _selectedTable,
                underline: const SizedBox(),
                items: _tables.map((t) {
                  return DropdownMenuItem<String>(
                    value: t['id'] as String,
                    child: Text(t['id'] as String, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.roleStaff)),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedTable = val);
                },
              ),
            ],
          ),
        ),
        const Divider(),

        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: _menuItems.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final item = _menuItems[index];
              final name = item['name'] as String;
              final price = item['price'] as int;
              final type = item['type'] as String;
              final icon = item['icon'] as IconData;
              final isBar = type == 'Bar';

              // Kiểm tra số lượng đã chọn của món hiện tại
              final currentQty = _cart[name]?.qty ?? 0;

              return Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      // Icon món
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: isBar ? AppColors.roleBar.withValues(alpha: 0.12) : AppColors.roleKitchen.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(icon, color: isBar ? AppColors.roleBar : AppColors.roleKitchen, size: 22),
                      ),
                      const SizedBox(width: 12),

                      // Thông tin tên món, loại và giá
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$type • ${_formatMoney(price)}',
                              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),

                      // Bộ điều khiển số lượng hoặc nút + Thêm ngay tại thẻ món
                      if (currentQty == 0)
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.roleStaff,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            minimumSize: const Size(0, 36),
                          ),
                          onPressed: () {
                            setState(() {
                              _cart[name] = CartItemData(
                                name: name,
                                price: price,
                                type: type,
                                icon: icon,
                                qty: 1,
                              );
                            });
                          },
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Thêm'),
                        )
                      else
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.roleStaff.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.roleStaff.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove, size: 16, color: AppColors.roleStaff),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                tooltip: 'Giảm số lượng',
                                onPressed: () {
                                  setState(() {
                                    if (_cart[name]!.qty > 1) {
                                      _cart[name]!.qty -= 1;
                                    } else {
                                      _cart.remove(name);
                                    }
                                  });
                                },
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                child: Text(
                                  '$currentQty',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: AppColors.roleStaff,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.add, size: 16, color: AppColors.roleStaff),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                tooltip: 'Tăng số lượng',
                                onPressed: () {
                                  setState(() {
                                    _cart[name]!.qty += 1;
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Bảng giỏ hàng bên phải (khi xem trên màn hình rộng)
  Widget _buildCartPanel() {
    final isCartEmpty = _cart.isEmpty;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Giỏ gọi món: $_selectedTable ($_totalItemsCount món)',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!isCartEmpty)
                IconButton(
                  icon: const Icon(Icons.delete_sweep_outlined, size: 20, color: Colors.red),
                  tooltip: 'Xóa giỏ',
                  onPressed: () => setState(() => _cart.clear()),
                ),
            ],
          ),
          const SizedBox(height: 12),

          Expanded(
            child: isCartEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.remove_shopping_cart_outlined, size: 48, color: AppColors.textSecondary),
                        SizedBox(height: 8),
                        Text(
                          'Chưa có món nào trong giỏ hàng.\nHãy nhấn nút "+ Thêm" trên danh sách.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                        ),
                      ],
                    ),
                  )
                : ListView(
                    children: _cart.entries.map((e) {
                      final item = e.value;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.name,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                  ),
                                  Text(
                                    _formatMoney(item.subtotal),
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.primary),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Đơn giá: ${_formatMoney(item.price)}',
                                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                  ),
                                  Row(
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.remove_circle_outline, size: 18),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                        onPressed: () {
                                          setState(() {
                                            if (item.qty > 1) {
                                              item.qty -= 1;
                                            } else {
                                              _cart.remove(e.key);
                                            }
                                          });
                                        },
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 4),
                                        child: Text('${item.qty}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.add_circle_outline, size: 18),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                        onPressed: () {
                                          setState(() => item.qty += 1);
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              // Ô nhập ghi chú món
                              const SizedBox(height: 4),
                              TextFormField(
                                initialValue: item.note,
                                style: const TextStyle(fontSize: 12),
                                decoration: const InputDecoration(
                                  hintText: 'Ghi chú (ít cay, không đá...)',
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (val) => item.note = val,
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
          ),
          const Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Flexible(
                child: Text(
                  'Tổng cộng tạm tính:',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(_formatMoney(_totalAmount), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: 12),

          // Nút gửi đơn - BỊ VÔ HIỆU HÓA khi giỏ hàng trống
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.roleStaff,
                disabledBackgroundColor: Colors.grey.shade300,
                disabledForegroundColor: Colors.grey.shade600,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: isCartEmpty ? null : _openOrderConfirmation,
              icon: const Icon(Icons.send_rounded),
              label: Text(
                isCartEmpty ? 'Chưa có món để gửi' : 'Gửi đơn tới Bếp & Bar',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Thanh giỏ hàng ở dưới (khi xem trên điện thoại)
  Widget _buildCartBottomBar() {
    final isCartEmpty = _cart.isEmpty;

    return Container(
      padding: const EdgeInsets.all(14),
      color: AppColors.surface,
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: isCartEmpty ? Colors.grey : AppColors.roleStaff,
            child: Text(
              '$_totalItemsCount',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Tạm tính: ${_formatMoney(_totalAmount)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                Text(
                  isCartEmpty ? 'Giỏ hàng đang trống' : 'Bàn $_selectedTable • $_totalItemsCount món',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.roleStaff,
              disabledBackgroundColor: Colors.grey.shade300,
              disabledForegroundColor: Colors.grey.shade600,
            ),
            onPressed: isCartEmpty ? null : _openOrderConfirmation,
            child: const Text('Gửi đơn'),
          ),
        ],
      ),
    );
  }

  /// Mở hộp thoại Xác nhận Đơn hàng trước khi gửi
  Future<void> _openOrderConfirmation() async {
    if (_cart.isEmpty) return;

    final itemsList = _cart.values.map((it) {
      return {
        'name': it.name,
        'price': it.price,
        'qty': it.qty,
        'type': it.type,
        'note': it.note,
      };
    }).toList();

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => OrderConfirmDialog(
        tableName: _selectedTable,
        items: itemsList,
        totalAmount: _totalAmount,
        onConfirm: () async {
          // Giả lập gửi đơn an toàn (demo trong bộ nhớ)
          await Future.delayed(const Duration(milliseconds: 500));

          // Cập nhật trạng thái bàn thành occupied trên Sơ đồ bàn
          final tableIndex = _tables.indexWhere((t) => t['id'] == _selectedTable);
          if (tableIndex != -1) {
            _tables[tableIndex]['status'] = 'occupied';
            _tables[tableIndex]['time'] = 'Vừa gọi';
            _tables[tableIndex]['total'] = _formatMoney(_totalAmount);
          }

          // Xóa sạch giỏ hàng sau khi gửi thành công
          _cart.clear();
        },
      ),
    );

    if (result == true && mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Đã gửi đơn thành công tới Bếp & Bar cho $_selectedTable!'),
              ),
            ],
          ),
          backgroundColor: AppColors.statusReady,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
}
