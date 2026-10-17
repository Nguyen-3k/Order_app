import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';

/// Hộp thoại xác nhận hoàn thành món cho Kitchen hoặc hoàn thành pha chế cho Bar
class StationConfirmDialog extends StatefulWidget {
  final String title;
  final String orderId;
  final String tableName;
  final String stationType; // 'Kitchen' | 'Bar'
  final Color themeColor;
  final IconData icon;
  final List<Map<String, dynamic>> items;
  final Future<void> Function() onConfirm;

  const StationConfirmDialog({
    super.key,
    required this.title,
    required this.orderId,
    required this.tableName,
    required this.stationType,
    required this.themeColor,
    required this.icon,
    required this.items,
    required this.onConfirm,
  });

  @override
  State<StationConfirmDialog> createState() => _StationConfirmDialogState();
}

class _StationConfirmDialogState extends State<StationConfirmDialog> {
  bool _isSubmitting = false;

  @override
  Widget build(BuildContext context) {
    final isKitchen = widget.stationType == 'Kitchen';
    final targetLabel = isKitchen ? 'Món ăn (Bếp)' : 'Đồ uống (Bar)';

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
              color: widget.themeColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(widget.icon, color: widget.themeColor, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                Text(
                  'Xác nhận chỉ các món thuộc phạm vi $targetLabel',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.normal),
                ),
              ],
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 380),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Thông tin Đơn và Bàn
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
                        const Icon(Icons.receipt_outlined, size: 16, color: AppColors.textSecondary),
                        const SizedBox(width: 6),
                        Text(
                          'Mã đơn: ${widget.orderId}',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: widget.themeColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        widget.tableName,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: widget.themeColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              Text(
                'Danh sách $targetLabel cần hoàn thành:',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 8),

              // Danh sách món với trạng thái
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: widget.items.asMap().entries.map((entry) {
                    final index = entry.key;
                    final it = entry.value;
                    final name = it['name'] as String;
                    final qty = it['qty'] as int;
                    final note = (it['note'] as String?) ?? '';
                    final currentStatus = isKitchen ? 'Đang nấu' : 'Đang pha';

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
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  name,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                ),
                              ),
                              Text(
                                'x$qty',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: widget.themeColor,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.statusPreparing.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  currentStatus,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.statusPreparing,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (note.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text(
                                '👉 Yêu cầu: $note',
                                style: const TextStyle(fontSize: 11, color: Colors.deepOrange, fontStyle: FontStyle.italic),
                              ),
                            ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.statusReady.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.statusReady.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline, size: 16, color: AppColors.statusReady),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Sau khi xác nhận, các món trên sẽ chuyển sang trạng thái "Sẵn sàng bưng" cho Phục vụ. Món thuộc quầy khác không bị thay đổi.',
                        style: TextStyle(fontSize: 11, color: Colors.green.shade900),
                      ),
                    ),
                  ],
                ),
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
          child: const Text('Quay lại'),
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
                          content: Text('Lỗi khi cập nhật trạng thái: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.themeColor,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
          icon: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.done_all_rounded, size: 18),
          label: Text(_isSubmitting ? 'Đang cập nhật...' : 'Xác nhận hoàn thành'),
        ),
      ],
    );
  }
}

