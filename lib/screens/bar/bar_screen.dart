import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../widgets/role_header_app_bar.dart';
import '../../widgets/station_confirm_dialog.dart';

/// Màn hình Quầy Pha Chế (Bar Display System - BDS)
class BarScreen extends StatefulWidget {
  const BarScreen({super.key});

  @override
  State<BarScreen> createState() => _BarScreenState();
}

class _BarScreenState extends State<BarScreen> {
  String _filter = 'Tất cả';

  // Dữ liệu mô phỏng danh sách vé đồ uống tại Quầy Bar (chỉ gồm Đồ uống / Pha chế)
  final List<Map<String, dynamic>> _barTickets = [
    {
      'id': '#BAR-201',
      'table': 'Bàn 02',
      'time': '2 phút trước',
      'status': 'pending', // pending, preparing, ready
      'items': [
        {'name': 'Trà đào cam sả', 'qty': 2, 'note': 'Ít đường, 70% đá'},
      ],
    },
    {
      'id': '#BAR-202',
      'table': 'Bàn 05',
      'time': '6 phút trước',
      'status': 'preparing',
      'items': [
        {'name': 'Cà phê muối', 'qty': 1, 'note': 'Nhiều bọt kem'},
        {'name': 'Sinh tố bơ sầu riêng', 'qty': 1, 'note': 'Ít ngọt'},
      ],
    },
    {
      'id': '#BAR-203',
      'table': 'Bàn 04',
      'time': '12 phút trước',
      'status': 'ready',
      'items': [
        {'name': 'Nước ép dưa hấu', 'qty': 2, 'note': 'Không đường, đá riêng'},
        {'name': 'Trà vải lài', 'qty': 1, 'note': ''},
      ],
    },
  ];

  @override
  Widget build(BuildContext context) {
    final filteredTickets = _barTickets.where((ticket) {
      if (_filter == 'Chờ pha') return ticket['status'] == 'pending';
      if (_filter == 'Đang pha') return ticket['status'] == 'preparing';
      if (_filter == 'Đã xong') return ticket['status'] == 'ready';
      return true;
    }).toList();

    return Scaffold(
      appBar: const RoleHeaderAppBar(
        title: 'Quầy Pha Chế (BDS)',
        roleName: 'Pha chế',
        roleColor: AppColors.roleBar,
        roleIcon: Icons.local_bar_rounded,
      ),
      body: Column(
        children: [
          // Banner mô phỏng
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: AppColors.roleBar.withValues(alpha: 0.08),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: AppColors.roleBar, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'BDS tự động lọc các Đồ uống & Tráng miệng cần pha chế. Nhấn nút trên vé để cập nhật tiến độ cho nhân viên phục vụ.',
                        style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Bộ lọc trạng thái
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: AppColors.surface,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip('Tất cả'),
                  const SizedBox(width: 8),
                  _buildFilterChip('Chờ pha'),
                  const SizedBox(width: 8),
                  _buildFilterChip('Đang pha'),
                  const SizedBox(width: 8),
                  _buildFilterChip('Đã xong'),
                ],
              ),
            ),
          ),
          const Divider(),

          // Lưới các vé đồ uống
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: filteredTickets.isEmpty
                      ? const Center(
                          child: Text(
                            'Hiện không có đơn đồ uống nào ở trạng thái này.',
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
                            return _buildBarTicketCard(filteredTickets[index]);
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
      selectedColor: AppColors.roleBar.withValues(alpha: 0.15),
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? AppColors.roleBar : AppColors.textPrimary,
      ),
    );
  }

  Widget _buildBarTicketCard(Map<String, dynamic> ticket) {
    final status = ticket['status'] as String;
    final isPending = status == 'pending';
    final isPreparing = status == 'preparing';
    final isReady = status == 'ready';

    Color statusColor = AppColors.statusPending;
    String statusText = 'Chờ pha';
    if (isPreparing) {
      statusColor = AppColors.statusPreparing;
      statusText = 'Đang pha';
    } else if (isReady) {
      statusColor = AppColors.statusReady;
      statusText = 'Đã xong';
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

            // Danh sách đồ uống cần pha
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
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.roleBar),
                          ),
                        ],
                      ),
                      if (note.isNotEmpty)
                        Text(
                          '🍹 Yêu cầu: $note',
                          style: const TextStyle(fontSize: 12, color: Colors.teal, fontStyle: FontStyle.italic),
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
                      ticket['status'] = 'preparing';
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Đang pha đồ uống cho ${ticket['table']}'), duration: const Duration(seconds: 1)),
                    );
                  },
                  icon: const Icon(Icons.blender_rounded, size: 18),
                  label: const Text('Bắt đầu pha'),
                ),
              )
            else if (isPreparing)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.statusReady),
                  onPressed: () async {
                    // Mở hộp thoại xác nhận hoàn thành pha chế riêng cho Bar
                    final confirmed = await showDialog<bool>(
                      context: context,
                      barrierDismissible: false,
                      builder: (ctx) => StationConfirmDialog(
                        title: 'XÁC NHẬN HOÀN THÀNH PHA CHẾ',
                        orderId: ticket['id'] as String,
                        tableName: ticket['table'] as String,
                        stationType: 'Bar',
                        themeColor: AppColors.roleBar,
                        icon: Icons.local_bar_rounded,
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
                          content: Text('Quầy Bar đã pha xong đồ uống cho ${ticket['table']}!'),
                          backgroundColor: AppColors.statusReady,
                          duration: const Duration(seconds: 2),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('Báo hoàn thành ly'),
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
                    '✓ Đồ uống đã sẵn sàng tại quầy',
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
