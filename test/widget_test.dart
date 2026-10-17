import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:order_app/main.dart';
import 'package:order_app/screens/staff/staff_screen.dart';
import 'package:order_app/screens/kitchen/kitchen_screen.dart';
import 'package:order_app/screens/bar/bar_screen.dart';

void main() {
  testWidgets('1. Smoke test: Màn hình chọn vai trò hiển thị đầy đủ 4 vai trò', (WidgetTester tester) async {
    await tester.pumpWidget(const SmartOrderApp());

    expect(find.text('Smart Order'), findsOneWidget);
    expect(find.text('Quản trị viên (Admin)'), findsOneWidget);
    expect(find.text('Nhân viên phục vụ (Staff)'), findsOneWidget);
    expect(find.text('Nhà bếp (Kitchen - KDS)'), findsOneWidget);
    expect(find.text('Quầy pha chế (Bar - BDS)'), findsOneWidget);
  });

  testWidgets('2. Staff: Điều khiển số lượng trên thẻ món và đồng bộ giỏ hàng', (WidgetTester tester) async {
    // Đặt kích thước màn hình test để hiển thị tốt cả 2 cột
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: StaffScreen(),
      ),
    );

    // Chuyển sang Tab 2: Tạo order
    await tester.tap(find.text('Tạo Order'));
    await tester.pumpAndSettle();

    // Ban đầu 'Cơm sườn nướng' chưa được chọn (có nút 'Thêm')
    expect(find.text('Cơm sườn nướng'), findsOneWidget);

    // Tìm và nhấn nút 'Thêm' tương ứng với Cơm sườn nướng
    final themButtons = find.widgetWithText(ElevatedButton, 'Thêm');
    expect(themButtons, findsWidgets);
    await tester.tap(themButtons.first);
    await tester.pumpAndSettle();

    // Sau khi thêm, số lượng hiển thị trên thẻ món
    expect(find.byIcon(Icons.remove), findsWidgets);
    expect(find.byIcon(Icons.add), findsWidgets);

    // Bấm nút "Gửi đơn tới Bếp & Bar" để mở hộp thoại XÁC NHẬN ĐƠN HÀNG
    final sendOrderButton = find.widgetWithText(ElevatedButton, 'Gửi đơn tới Bếp & Bar');
    expect(sendOrderButton, findsOneWidget);
    await tester.tap(sendOrderButton);
    await tester.pumpAndSettle();

    // Kiểm tra hộp thoại xác nhận
    expect(find.text('XÁC NHẬN ĐƠN HÀNG'), findsOneWidget);
    expect(find.text('Quay lại chỉnh sửa'), findsOneWidget);
    expect(find.text('Xác nhận gửi đơn'), findsOneWidget);

    // Bấm "Quay lại chỉnh sửa" -> hộp thoại đóng và dữ liệu giỏ hàng giữ nguyên
    await tester.tap(find.text('Quay lại chỉnh sửa'));
    await tester.pumpAndSettle();
    expect(find.text('XÁC NHẬN ĐƠN HÀNG'), findsNothing);
  });

  testWidgets('3. Kitchen: Hộp thoại xác nhận hoàn thành món', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: KitchenScreen(),
      ),
    );

    // Tìm vé đang ở trạng thái 'Đang nấu' có nút 'Báo hoàn thành món'
    final completeButton = find.widgetWithText(ElevatedButton, 'Báo hoàn thành món');
    expect(completeButton, findsWidgets);

    // Bấm nút báo hoàn thành
    await tester.tap(completeButton.first);
    await tester.pumpAndSettle();

    // Hộp thoại xuất hiện với tiêu đề chuẩn
    expect(find.text('XÁC NHẬN HOÀN THÀNH MÓN'), findsOneWidget);
    expect(find.text('Quay lại'), findsOneWidget);
    expect(find.text('Xác nhận hoàn thành'), findsOneWidget);

    // Thử bấm Quay lại -> không đổi trạng thái
    await tester.tap(find.text('Quay lại'));
    await tester.pumpAndSettle();
    expect(find.text('XÁC NHẬN HOÀN THÀNH MÓN'), findsNothing);
  });

  testWidgets('4. Bar: Hộp thoại xác nhận hoàn thành pha chế', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: BarScreen(),
      ),
    );

    // Tìm nút 'Báo hoàn thành ly'
    final completeButton = find.widgetWithText(ElevatedButton, 'Báo hoàn thành ly');
    expect(completeButton, findsWidgets);

    // Bấm nút báo hoàn thành ly
    await tester.tap(completeButton.first);
    await tester.pumpAndSettle();

    // Hộp thoại xuất hiện với tiêu đề chuẩn
    expect(find.text('XÁC NHẬN HOÀN THÀNH PHA CHẾ'), findsOneWidget);
    expect(find.text('Quay lại'), findsOneWidget);
    expect(find.text('Xác nhận hoàn thành'), findsOneWidget);

    // Thử bấm Quay lại
    await tester.tap(find.text('Quay lại'));
    await tester.pumpAndSettle();
    expect(find.text('XÁC NHẬN HOÀN THÀNH PHA CHẾ'), findsNothing);
  });
}
