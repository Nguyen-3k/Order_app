import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';

/// Hộp thoại Xác nhận Đơn hàng trước khi gửi tới Bếp và Bar
class OrderConfirmDialog extends StatefulWidget {
  final String tableName;
  final List<Map<String, dynamic>> items;
  final int totalAmount;
  final Future<void> Function() onConfirm;

  const OrderConfirmDialog({
    super.key,
    required this.tableName,
    required this.items,
    required this.totalAmount,
    required this.onConfirm,
  });

  @override
  State<OrderConfirmDialog> createState() => _OrderConfirmDialogState();
}

class _OrderConfirmDialogState extends State<OrderConfirmDialog> {
  bool _isSubmitting = false;

  String _formatMoney(int amount) {
    return '${amount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')} đ';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      actionsPadding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.roleStaff.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.receipt_long_rounded, color: AppColors.roleStaff, size: 24),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'XÁC NHẬN ĐƠN HÀNG',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                Text(
                  'Kiểm tra lại danh sách món trước khi gửi',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.normal),
                ),
              ],
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Thông tin bàn
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.table_restaurant, size: 18, color: AppColors.roleStaff),
                        const SizedBox(width: 8),
                        const Text('Bàn phục vụ:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      ],
                    ),
                    Text(
                      widget.tableName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.roleStaff),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              const Text(
                'Chi tiết các món đã chọn:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 8),

              // Bảng danh sách món
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: widget.items.asMap().entries.map((entry) {
                    final index = entry.key;
                    final item = entry.value;
                    final name = item['name'] as String;
                    final price = item['price'] as int;
                    final qty = item['qty'] as int;
                    final note = (item['note'] as String?) ?? '';
                    final type = item['type'] as String? ?? 'Bếp';
                    final subtotal = price * qty;
                    final isBar = type == 'Bar';

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: index.isEven ? Colors.transparent : AppColors.surfaceVariant.withValues(alpha: 0.4),
                        border: index == widget.items.length - 1
                            ? null
                            : const Border(bottom: BorderSide(color: AppColors.border)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isBar
                                      ? AppColors.roleBar.withValues(alpha: 0.12)
                                      : AppColors.roleKitchen.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  type,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: isBar ? AppColors.roleBar : AppColors.roleKitchen,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  name,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                ),
                              ),
                              Text(
                                'x$qty',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.roleStaff),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                _formatMoney(subtotal),
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 36, top: 2),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Đơn giá: ${_formatMoney(price)}',
                                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                ),
                                if (note.isNotEmpty)
                                  Flexible(
                                    child: Text(
                                      'Ghi chú: $note',
                                      style: const TextStyle(fontSize: 11, color: Colors.deepOrange, fontStyle: FontStyle.italic),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(height: 12),
              // Tổng cộng
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'TỔNG TIỀN ĐƠN HÀNG:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    Text(
                      _formatMoney(widget.totalAmount),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),
              const Row(
                children: [
                  Icon(Icons.info_outline, size: 14, color: AppColors.textSecondary),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Chế độ demo bộ nhớ: Dữ liệu đơn hàng sẽ được gửi cục bộ tới danh sách Bếp và Bar.',
                      style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(false),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textSecondary,
            side: const BorderSide(color: AppColors.border),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          child: const Text('Quay lại chỉnh sửa'),
        ),
        ElevatedButton.icon(
          onPressed: _isSubmitting
              ? null
              : () async {
                  setState(() => _isSubmitting = true);
                  try {
                    await widget.onConfirm();
                    if (context.mounted) {
                      Navigator.of(context).pop(true);
                    }
                  } catch (e) {
                    if (context.mounted) {
                      setState(() => _isSubmitting = false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Lỗi khi gửi đơn: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.roleStaff,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          icon: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.check_circle_outline, size: 18),
          label: Text(_isSubmitting ? 'Đang gửi...' : 'Xác nhận gửi đơn'),
        ),
      ],
    );
  }
}

