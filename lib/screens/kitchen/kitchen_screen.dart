import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../widgets/role_header_app_bar.dart';
import '../../widgets/station_confirm_dialog.dart';

/// Màn hình Nhà Bếp (Kitchen Display System - KDS)
class KitchenScreen extends StatefulWidget {
  const KitchenScreen({super.key});

  @override
  State<KitchenScreen> createState() => _KitchenScreenState();
}

class _KitchenScreenState extends State<KitchenScreen> {
  String _filter = 'Tất cả';

  // Dữ liệu mô phỏng danh sách vé gọi món tại Bếp (chỉ gồm Món ăn, không có Đồ uống)
  final List<Map<String, dynamic>> _kitchenTickets = [
    {
      'id': '#ORD-101',
      'table': 'Bàn 02',
      'time': '3 phút trước',
      'status': 'pending', // pending, cooking, ready
      'items': [
        {'name': 'Bò lúc lắc khoai tây', 'qty': 1, 'note': 'Ít tiêu, bò chín vừa'},
        {'name': 'Mì xào hải sản', 'qty': 1, 'note': 'Không hành lá'},
      ],
    },
    {
      'id': '#ORD-102',
      'table': 'Bàn 04',
      'time': '8 phút trước',
      'status': 'cooking',
      'items': [
        {'name': 'Cơm sườn nướng mật ong', 'qty': 2, 'note': 'Thêm cơm thêm'},
        {'name': 'Canh rong biển thịt bằm', 'qty': 1, 'note': ''},
      ],
    },
    {
      'id': '#ORD-103',
      'table': 'Bàn 07',
      'time': '15 phút trước',
      'status': 'cooking',
      'items': [
        {'name': 'Lẩu Thái hải sản', 'qty': 1, 'note': 'Cay nhiều, thêm bún tươi'},
      ],
    },
    {
      'id': '#ORD-104',
      'table': 'Bàn 10',
      'time': '22 phút trước',
      'status': 'ready',
      'items': [
        {'name': 'Cơm chiên cá mặn', 'qty': 1, 'note': ''},
      ],
    },
  ];

  @override
  Widget build(BuildContext context) {
    final filteredTickets = _kitchenTickets.where((ticket) {
      if (_filter == 'Chờ nấu') return ticket['status'] == 'pending';
      if (_filter == 'Đang nấu') return ticket['status'] == 'cooking';
      if (_filter == 'Hoàn thành') return ticket['status'] == 'ready';
      return true;
    }).toList();

    return Scaffold(
      appBar: const RoleHeaderAppBar(
        title: 'Màn Hình Bếp (KDS)',
        roleName: 'Nhà bếp',
        roleColor: AppColors.roleKitchen,
        roleIcon: Icons.soup_kitchen_rounded,
      ),
      body: Column(
        children: [
          // Banner mô phỏng
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: AppColors.roleKitchen.withValues(alpha: 0.08),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: AppColors.roleKitchen, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'KDS tự động lọc các Món ăn (Food) cần chế biến. Nhấn vào nút thao tác trên từng vé để cập nhật tiến độ.',
                        style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Thanh bộ lọc trạng thái
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: AppColors.surface,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip('Tất cả'),
                  const SizedBox(width: 8),
                  _buildFilterChip('Chờ nấu'),
                  const SizedBox(width: 8),
                  _buildFilterChip('Đang nấu'),
                  const SizedBox(width: 8),
                  _buildFilterChip('Hoàn thành'),
                ],
              ),
            ),
          ),
          const Divider(),

          // Lưới các vé đơn cần nấu
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: filteredTickets.isEmpty
                      ? const Center(
                          child: Text(
                            'Hiện không có đơn nào ở trạng thái này.',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        )
                      : GridView.builder(
                          itemCount: filteredTickets.length,
                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 340,
                            mainAxisSpacing: 16,
                            crossAxisSpacing: 16,
                            childAspectRatio: 0.95,
                          ),
                          itemBuilder: (context, index) {
                            return _buildKitchenTicketCard(filteredTickets[index]);
                          },
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label) {
    final isSelected = _filter == label;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) setState(() => _filter = label);
      },
      selectedColor: AppColors.roleKitchen.withValues(alpha: 0.15),
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? AppColors.roleKitchen : AppColors.textPrimary,
      ),
    );
  }

  Widget _buildKitchenTicketCard(Map<String, dynamic> ticket) {
    final status = ticket['status'] as String;
    final isPending = status == 'pending';
    final isCooking = status == 'cooking';
    final isReady = status == 'ready';

    Color statusColor = AppColors.statusPending;
    String statusText = 'Chờ nấu';
    if (isCooking) {
      statusColor = AppColors.statusPreparing;
      statusText = 'Đang nấu';
    } else if (isReady) {
      statusColor = AppColors.statusReady;
      statusText = 'Hoàn thành';
    }

    final items = ticket['items'] as List<Map<String, dynamic>>;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: statusColor, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Tiêu đề vé: Bàn + Mã order + Tag trạng thái
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ticket['table'] as String,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      Text(
                        ticket['id'] as String,
                        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '⏱ ${ticket['time']}',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const Divider(height: 16),

            // Danh sách món ăn cần nấu
            Expanded(
              child: ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (context, i) {
                  final it = items[i];
                  final note = it['note'] as String;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              it['name'] as String,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                          ),
                          Text(
                            'x${it['qty']}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.roleKitchen),
                          ),
                        ],
                      ),
                      if (note.isNotEmpty)
                        Text(
                          '👉 Lưu ý: $note',
                          style: const TextStyle(fontSize: 12, color: Colors.redAccent, fontStyle: FontStyle.italic),
                        ),
                    ],
                  );
                },
              ),
            ),

            const SizedBox(height: 8),
            // Nút chuyển trạng thái
            if (isPending)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.statusPreparing),
                  onPressed: () {
                    setState(() {
                      ticket['status'] = 'cooking';
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Đã nhận nấu đơn ${ticket['table']}'), duration: const Duration(seconds: 1)),
                    );
                  },
                  icon: const Icon(Icons.microwave_rounded, size: 18),
                  label: const Text('Bắt đầu nấu'),
                ),
              )
            else if (isCooking)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.statusReady),
                  onPressed: () async {
                    // Mở hộp thoại xác nhận hoàn thành món riêng cho Kitchen
                    final confirmed = await showDialog<bool>(
                      context: context,
                      barrierDismissible: false,
                      builder: (ctx) => StationConfirmDialog(
                        title: 'XÁC NHẬN HOÀN THÀNH MÓN',
                        orderId: ticket['id'] as String,
                        tableName: ticket['table'] as String,
                        stationType: 'Kitchen',
                        themeColor: AppColors.roleKitchen,
                        icon: Icons.soup_kitchen_rounded,
                        items: items,
                        onConfirm: () async {
                          await Future.delayed(const Duration(milliseconds: 400));
                          ticket['status'] = 'ready';
                        },
                      ),
                    );

                    if (confirmed == true && mounted) {
                      setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Bếp đã hoàn thành các món cho ${ticket['table']}! Sẵn sàng bưng cho khách.'),
                          backgroundColor: AppColors.statusReady,
                          duration: const Duration(seconds: 2),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('Báo hoàn thành món'),
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.statusReady.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Text(
                    '✓ Món đã sẵn sàng bưng cho khách',
                    style: TextStyle(color: AppColors.statusReady, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
