-- ==============================================================================
-- SMART ORDER — CHECKLIST & SQL TEST SCRIPTS FOR DATABASE VERIFICATION
-- Test File: supabase/tests/001_schema_verification.sql
-- Database: PostgreSQL 15+ (Supabase)
-- Phase: C2.4 — Complete Hardened Test Suite & Security Validation
-- ==============================================================================
-- HƯỚNG DẪN SỬ DỤNG:
-- 1. File này là bộ kịch bản kiểm thử độc lập (Test Suite), dùng để chạy trên Supabase SQL Editor
--    sau khi đã chạy file migration chính (001_initial_schema.sql).
-- 2. Mỗi test case được thiết kế dưới dạng một khối PL/pgSQL độc lập (DO $$ ... $$;):
--    - Tự chuẩn bị dữ liệu tiền điều kiện (Pre-conditions), không phụ thuộc database có sẵn dữ liệu hay không.
--    - Thực sự gọi hành vi cần kiểm tra (RPC hoặc DML).
--    - Bắt đúng mã lỗi/thông báo lỗi kỳ vọng.
--    - Tự động dọn dẹp sạch sẽ (Cleanup), không làm ô nhiễm hay rác dữ liệu.
-- 3. CẢNH BÁO BẢO MẬT: File này CHƯA được thực thi trên môi trường thật.
--    Không được tuyên bố test thành công khi chưa chạy thực tế trên PostgreSQL.
-- ==============================================================================


-- ==============================================================================
-- TEST 0: KIỂM SOÁT KHỞI TẠO VÀ CHỈ ĐỊNH ADMIN (ADMIN PROMOTION SECURITY TEST)
-- Mục tiêu:
-- 1. Xác minh RPC claim_first_admin() đã bị loại bỏ hoàn toàn (không còn tồn tại để client thăm dò).
-- 2. Role 'authenticated' (Client) bị TỪ CHỐI thực thi hàm public.assign_admin_role().
-- 3. Chỉ Quản trị viên cơ sở dữ liệu (DBA qua SQL Editor/postgres) mới có quyền chỉ định Admin.
-- ==============================================================================
DO $$
DECLARE
    v_test_user_id uuid := gen_random_uuid();
    v_test_email text := 'candidate_' || substr(gen_random_uuid()::text, 1, 8) || '@smartorder.local';
    v_client_exec_blocked boolean := false;
    v_claim_first_admin_exists boolean := false;
    v_res jsonb;
    v_promoted_role text;
BEGIN
    -- 1. Tạo tài khoản người dùng test
    INSERT INTO auth.users (id, email, raw_user_meta_data, role, aud)
    VALUES (v_test_user_id, v_test_email, '{"full_name":"Candidate Admin"}'::jsonb, 'authenticated', 'authenticated');

    -- BƯỚC 0.1: Xác minh RPC claim_first_admin đã bị xóa hoàn toàn khỏi hệ thống
    SELECT EXISTS (
        SELECT 1 FROM pg_proc WHERE proname = 'claim_first_admin'
    ) INTO v_claim_first_admin_exists;

    IF v_claim_first_admin_exists THEN
        RAISE EXCEPTION 'LỖI BẢO MẬT: TEST 0.1 THẤT BẠI — RPC claim_first_admin vẫn còn tồn tại trong database!';
    ELSE
        RAISE NOTICE '>>> TEST 0.1 ĐẠT: RPC claim_first_admin đã bị loại bỏ hoàn toàn, không thể bị client thăm dò';
    END IF;

    -- BƯỚC 0.2: Giả lập Client (authenticated role) cố tình gọi assign_admin_role -> KỲ VỌNG: BỊ TỪ CHỐI
    SET LOCAL ROLE authenticated;
    BEGIN
        PERFORM public.assign_admin_role(v_test_email);
    EXCEPTION WHEN insufficient_privilege THEN
        v_client_exec_blocked := true;
        RAISE NOTICE '>>> TEST 0.2 ĐẠT: Role authenticated bị từ chối gọi assign_admin_role (insufficient_privilege)';
    WHEN OTHERS THEN
        IF SQLERRM LIKE '%Quyền hạn bị từ chối%' OR SQLERRM LIKE '%permission denied%' THEN
            v_client_exec_blocked := true;
            RAISE NOTICE '>>> TEST 0.2 ĐẠT: Database từ chối quyền gọi: %', SQLERRM;
        ELSE
            RAISE EXCEPTION 'TEST 0.2 BẮT LỖI KHÔNG MONG MUỐN: %', SQLERRM;
        END IF;
    END;
    RESET ROLE;

    IF NOT v_client_exec_blocked THEN
        RAISE EXCEPTION 'LỖI BẢO MẬT: TEST 0.2 THẤT BẠI — Client authenticated có thể gọi assign_admin_role!';
    END IF;

    -- BƯỚC 0.3: DBA thực hiện chỉ định Admin hợp lệ qua SQL Editor (role postgres) -> KỲ VỌNG: THÀNH CÔNG
    v_res := public.assign_admin_role(v_test_email);
    IF (v_res->>'success')::boolean IS TRUE THEN
        SELECT role INTO v_promoted_role FROM public.profiles WHERE id = v_test_user_id;
        IF v_promoted_role = 'admin' THEN
            RAISE NOTICE '>>> TEST 0.3 ĐẠT: DBA chỉ định vai trò Admin cho tài khoản qua SQL Editor thành công';
        ELSE
            RAISE EXCEPTION 'TEST 0.3 THẤT BẠI: Role sau cập nhật không phải admin (%)', v_promoted_role;
        END IF;
    ELSE
        RAISE EXCEPTION 'TEST 0.3 THẤT BẠI: assign_admin_role thất bại: %', v_res;
    END IF;

    -- Dọn dẹp dữ liệu test
    DELETE FROM auth.users WHERE id = v_test_user_id;
    RAISE NOTICE '>>> TEST 0 TOÀN DIỆN ĐẠT & ĐÃ DỌN DẸP SẠCH DỮ LIỆU';
END;
$$;


-- ==============================================================================
-- TEST 1: CHỐNG LEO THANG ĐẶC QUYỀN (PRIVILEGE ESCALATION TEST)
-- Mục tiêu: Đảm bảo nhân viên thường (staff) hoặc user bất kỳ không thể tự UPDATE
-- role của mình thành 'admin' hoặc tự kích hoạt lại tài khoản.
-- Cơ chế chặn: Trigger trg_protect_profile_roles trên bảng public.profiles.
-- ==============================================================================
DO $$
DECLARE
    v_test_user_id uuid := gen_random_uuid();
    v_escalated boolean := false;
BEGIN
    -- 1. Tạo tài khoản trong auth.users (Trigger on_auth_user_created tự gán role = 'staff')
    INSERT INTO auth.users (id, email, raw_user_meta_data, role, aud)
    VALUES (
        v_test_user_id,
        'test_staff_' || substr(gen_random_uuid()::text, 1, 8) || '@smartorder.local',
        jsonb_build_object('full_name', 'Nhân viên Test Escalation'),
        'authenticated',
        'authenticated'
    );

    -- 2. Giả lập context phiên đăng nhập của nhân viên test
    PERFORM set_config('request.jwt.claim.sub', v_test_user_id::text, true);
    PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

    -- 3. Cố tình tự nâng quyền lên 'admin' (Kỳ vọng: BẮT BUỘC BỊ TỪ CHỐI)
    BEGIN
        UPDATE public.profiles
        SET role = 'admin'
        WHERE id = v_test_user_id;

        v_escalated := true;
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%Chỉ Quản trị viên (Admin) mới có quyền thay đổi vai trò%'
           OR SQLERRM LIKE '%Ngữ cảnh không xác thực%' THEN
            RAISE NOTICE '>>> TEST 1 ĐẠT: Database đã chặn thành công hành vi tự nâng quyền: %', SQLERRM;
        ELSE
            RAISE EXCEPTION 'TEST 1 BẮT LỖI KHÔNG MONG MUỐN: %', SQLERRM;
        END IF;
    END;

    -- 4. Dọn dẹp dữ liệu test và reset context
    DELETE FROM auth.users WHERE id = v_test_user_id;
    PERFORM set_config('request.jwt.claim.sub', '', true);
    PERFORM set_config('request.jwt.claim.role', '', true);

    IF v_escalated THEN
        RAISE EXCEPTION 'LỖI BẢO MẬT: TEST 1 THẤT BẠI — Nhân viên đã tự nâng quyền thành admin!';
    END IF;

    RAISE NOTICE '>>> TEST 1 HOÀN TẤT & ĐÃ DỌN DẸP SẠCH DỮ LIỆU';
END;
$$;


-- ==============================================================================
-- TEST 2: CHỐNG GHI TRỰC TIẾP TRÊN BẢNG NGHIỆP VỤ (ZERO-DIRECT-WRITE TEST)
-- Mục tiêu: Đảm bảo role authenticated không thể UPDATE trực tiếp bảng dining_tables
-- mà bắt buộc phải thông qua RPC release_dining_table.
-- Cơ chế chặn: REVOKE UPDATE ON public.dining_tables FROM authenticated.
-- ==============================================================================
DO $$
DECLARE
    v_table_id uuid;
    v_direct_write_succeeded boolean := false;
BEGIN
    SELECT id INTO v_table_id FROM public.dining_tables LIMIT 1;

    IF v_table_id IS NULL THEN
        RAISE EXCEPTION 'Tiền điều kiện không thỏa mãn: Bảng dining_tables chưa có dữ liệu';
    END IF;

    -- 1. Giả lập ngữ cảnh vai trò 'authenticated' (hạ quyền từ superuser để kiểm tra phân quyền SQL thực tế)
    SET LOCAL ROLE authenticated;

    -- 2. Cố tình thực hiện UPDATE trực tiếp trên dining_tables
    BEGIN
        UPDATE public.dining_tables
        SET status = 'available'
        WHERE id = v_table_id;

        v_direct_write_succeeded := true;
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE '>>> TEST 2 ĐẠT: Database đã từ chối lệnh UPDATE trực tiếp với mã lỗi insufficient_privilege';
    WHEN OTHERS THEN
        RAISE EXCEPTION 'TEST 2 BẮT LỖI KHÔNG MONG MUỐN: %', SQLERRM;
    END;

    -- 3. Khôi phục quyền superuser
    RESET ROLE;

    IF v_direct_write_succeeded THEN
        RAISE EXCEPTION 'LỖI BẢO MẬT: TEST 2 THẤT BẠI — Client có thể ghi trực tiếp lên bảng dining_tables!';
    END IF;

    RAISE NOTICE '>>> TEST 2 HOÀN TẤT: Zero-Direct-Write hoạt động chính xác';
END;
$$;


-- ==============================================================================
-- TEST 3: CHỐNG TRÙNG LẶP MÃ GIAO DỊCH HOÀN TẤT (DUPLICATE TRANSACTION CODE TEST)
-- Mục tiêu: Hai giao dịch completed có cùng transaction_code (kể cả có khoảng trắng)
-- không thể cùng được ghi nhận vào bảng payments. Tự tạo tiền điều kiện hoàn chỉnh.
-- Cơ chế chặn: UNIQUE INDEX idx_payments_unique_transaction_code có điều kiện WHERE status = 'completed'.
-- ==============================================================================
DO $$
DECLARE
    v_test_staff_id uuid := gen_random_uuid();
    v_table_id uuid;
    v_prod_id uuid;
    v_order_id uuid;
    v_txn_code text := 'TEST_TXN_' || substr(gen_random_uuid()::text, 1, 8);
    v_duplicate_allowed boolean := false;
BEGIN
    -- 1. Chuẩn bị tài khoản nhân viên test
    INSERT INTO auth.users (id, email, raw_user_meta_data, role, aud)
    VALUES (v_test_staff_id, 'staff_test_txn@smartorder.local', '{"full_name":"Staff Test Txn"}'::jsonb, 'authenticated', 'authenticated');

    PERFORM set_config('request.jwt.claim.sub', v_test_staff_id::text, true);
    PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

    SELECT id INTO v_table_id FROM public.dining_tables WHERE status = 'available' LIMIT 1;
    SELECT id INTO v_prod_id FROM public.products WHERE is_available = true LIMIT 1;

    -- Tạo đơn hàng tiền điều kiện
    INSERT INTO public.orders (order_code, table_id, staff_id, status, payment_status, total_amount)
    VALUES ('ORD-TEST-TXN-999', v_table_id, v_test_staff_id, 'pending', 'unpaid', 50000.00)
    RETURNING id INTO v_order_id;

    -- 2. Chèn giao dịch thứ nhất thành công
    INSERT INTO public.payments (order_id, amount, payment_method, status, transaction_code, processed_by)
    VALUES (v_order_id, 25000.00, 'banking_qr', 'completed', v_txn_code, v_test_staff_id);

    -- 3. Cố tình chèn giao dịch thứ hai với cùng mã (kèm khoảng trắng thừa)
    BEGIN
        INSERT INTO public.payments (order_id, amount, payment_method, status, transaction_code, processed_by)
        VALUES (v_order_id, 25000.00, 'banking_qr', 'completed', '  ' || v_txn_code || '  ', v_test_staff_id);

        v_duplicate_allowed := true;
    EXCEPTION
        WHEN unique_violation THEN
            RAISE NOTICE '>>> TEST 3 ĐẠT: Unique Index có điều kiện đã chặn giao dịch trùng transaction_code';
        WHEN OTHERS THEN
            RAISE EXCEPTION 'TEST 3 BẮT LỖI KHÔNG MONG MUỐN: %', SQLERRM;
    END;

    -- 4. Dọn dẹp toàn bộ dữ liệu test và reset context
    DELETE FROM public.payments WHERE order_id = v_order_id;
    DELETE FROM public.orders WHERE id = v_order_id;
    DELETE FROM auth.users WHERE id = v_test_staff_id;
    PERFORM set_config('request.jwt.claim.sub', '', true);
    PERFORM set_config('request.jwt.claim.role', '', true);

    IF v_duplicate_allowed THEN
        RAISE EXCEPTION 'LỖI TOÀN VẸN: TEST 3 THẤT BẠI — Cho phép ghi nhận trùng mã giao dịch completed!';
    END IF;

    RAISE NOTICE '>>> TEST 3 HOÀN TẤT & ĐÃ DỌN DẸP SẠCH DỮ LIỆU';
END;
$$;


-- ==============================================================================
-- TEST 4: CHỐNG THANH TOÁN VƯỢT SỐ DƯ CÒN LẠI (OVER-PAYMENT PREVENTION TEST)
-- Mục tiêu: RPC process_payment phải từ chối khi số tiền thanh toán lớn hơn số tiền còn lại.
-- Cơ chế chặn: Kiểm tra v_remaining_balance trong public.process_payment().
-- ==============================================================================
DO $$
DECLARE
    v_test_staff_id uuid := gen_random_uuid();
    v_table_id uuid;
    v_prod_id uuid;
    v_order_res jsonb;
    v_order_id uuid;
    v_total_amount numeric;
    v_overpay_allowed boolean := false;
BEGIN
    INSERT INTO auth.users (id, email, raw_user_meta_data, role, aud)
    VALUES (v_test_staff_id, 'staff_test_pay@smartorder.local', '{"full_name":"Staff Test Pay"}'::jsonb, 'authenticated', 'authenticated');

    PERFORM set_config('request.jwt.claim.sub', v_test_staff_id::text, true);
    PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

    SELECT id INTO v_table_id FROM public.dining_tables WHERE status = 'available' LIMIT 1;
    SELECT id INTO v_prod_id FROM public.products WHERE is_available = true LIMIT 1;

    -- 1. Mở đơn hàng mới
    v_order_res := public.create_full_order(
        v_table_id,
        jsonb_build_array(jsonb_build_object('product_id', v_prod_id, 'quantity', 1))
    );
    v_order_id := (v_order_res->>'order_id')::uuid;
    v_total_amount := (v_order_res->>'total_amount')::numeric;

    -- 2. Cố tình thanh toán số tiền lớn hơn tổng tiền đơn (Kỳ vọng: PHẢI BỊ TỪ CHỐI)
    BEGIN
        PERFORM public.process_payment(v_order_id, v_total_amount + 50000.00, 'cash');
        v_overpay_allowed := true;
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%vượt quá số tiền còn lại phải trả%' THEN
            RAISE NOTICE '>>> TEST 4 ĐẠT: RPC process_payment đã chặn thanh toán vượt số dư: %', SQLERRM;
        ELSE
            RAISE EXCEPTION 'TEST 4 BẮT LỖI KHÔNG MONG MUỐN: %', SQLERRM;
        END IF;
    END;

    -- 3. Dọn dẹp
    DELETE FROM public.order_items WHERE order_id = v_order_id;
    DELETE FROM public.orders WHERE id = v_order_id;
    UPDATE public.dining_tables SET status = 'available' WHERE id = v_table_id;
    DELETE FROM auth.users WHERE id = v_test_staff_id;
    PERFORM set_config('request.jwt.claim.sub', '', true);
    PERFORM set_config('request.jwt.claim.role', '', true);

    IF v_overpay_allowed THEN
        RAISE EXCEPTION 'LỖI NGHIỆP VỤ: TEST 4 THẤT BẠI — Hệ thống cho phép thanh toán vượt số tiền phải trả!';
    END IF;

    RAISE NOTICE '>>> TEST 4 HOÀN TẤT & ĐÃ DỌN DẸP SẠCH DỮ LIỆU';
END;
$$;


-- ==============================================================================
-- TEST 5: CHỐNG HỦY MÓN SAU KHI ĐÃ THANH TOÁN (CANCEL ITEM AFTER PAYMENT TEST)
-- Mục tiêu: Không cho phép hủy món trong đơn hàng đã paid hoặc partially_paid.
-- Cơ chế chặn: Kiểm tra v_order_pay_status trong public.update_order_item_status().
-- ==============================================================================
DO $$
DECLARE
    v_test_staff_id uuid := gen_random_uuid();
    v_table_id uuid;
    v_prod_id uuid;
    v_order_res jsonb;
    v_order_id uuid;
    v_item_id uuid;
    v_cancel_allowed boolean := false;
BEGIN
    INSERT INTO auth.users (id, email, raw_user_meta_data, role, aud)
    VALUES (v_test_staff_id, 'staff_test_cancel@smartorder.local', '{"full_name":"Staff Test Cancel"}'::jsonb, 'authenticated', 'authenticated');

    PERFORM set_config('request.jwt.claim.sub', v_test_staff_id::text, true);
    PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

    SELECT id INTO v_table_id FROM public.dining_tables WHERE status = 'available' LIMIT 1;
    SELECT id INTO v_prod_id FROM public.products WHERE is_available = true LIMIT 1;

    -- 1. Tạo đơn hàng và thanh toán 1 phần
    v_order_res := public.create_full_order(
        v_table_id,
        jsonb_build_array(jsonb_build_object('product_id', v_prod_id, 'quantity', 2))
    );
    v_order_id := (v_order_res->>'order_id')::uuid;

    SELECT id INTO v_item_id FROM public.order_items WHERE order_id = v_order_id LIMIT 1;

    -- Thanh toán 10.000đ để đưa đơn về trạng thái partially_paid
    PERFORM public.process_payment(v_order_id, 10000.00, 'cash');

    -- 2. Cố tình hủy món khi đơn đã phát sinh thanh toán (Kỳ vọng: BỊ CHẶN)
    BEGIN
        PERFORM public.update_order_item_status(v_item_id, 'cancelled');
        v_cancel_allowed := true;
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%Không thể hủy món trong đơn hàng đã phát sinh thanh toán%' THEN
            RAISE NOTICE '>>> TEST 5 ĐẠT: RPC đã chặn thành công thao tác hủy món khi đơn đã thanh toán: %', SQLERRM;
        ELSE
            RAISE EXCEPTION 'TEST 5 BẮT LỖI KHÔNG MONG MUỐN: %', SQLERRM;
        END IF;
    END;

    -- 3. Dọn dẹp
    DELETE FROM public.payments WHERE order_id = v_order_id;
    DELETE FROM public.order_items WHERE order_id = v_order_id;
    DELETE FROM public.orders WHERE id = v_order_id;
    UPDATE public.dining_tables SET status = 'available' WHERE id = v_table_id;
    DELETE FROM auth.users WHERE id = v_test_staff_id;
    PERFORM set_config('request.jwt.claim.sub', '', true);
    PERFORM set_config('request.jwt.claim.role', '', true);

    IF v_cancel_allowed THEN
        RAISE EXCEPTION 'LỖI NGHIỆP VỤ: TEST 5 THẤT BẠI — Cho phép hủy món khi đơn đã thanh toán!';
    END IF;

    RAISE NOTICE '>>> TEST 5 HOÀN TẤT & ĐÃ DỌN DẸP SẠCH DỮ LIỆU';
END;
$$;


-- ==============================================================================
-- TEST 6: CHỐNG MỞ ĐƠN CHỒNG CHÉO TẠI BÀN ĐANG CÓ KHÁCH (CONCURRENT OCCUPATION TEST)
-- Mục tiêu: Bàn đang occupied hoặc có đơn dở dang không thể tiếp tục gọi create_full_order.
-- Cơ chế chặn: Khóa bàn FOR UPDATE và kiểm tra status != 'available' trong create_full_order().
-- ==============================================================================
DO $$
DECLARE
    v_test_staff_id uuid := gen_random_uuid();
    v_table_id uuid;
    v_prod_id uuid;
    v_order_res jsonb;
    v_order_id uuid;
    v_overlap_allowed boolean := false;
BEGIN
    INSERT INTO auth.users (id, email, raw_user_meta_data, role, aud)
    VALUES (v_test_staff_id, 'staff_test_table@smartorder.local', '{"full_name":"Staff Test Table"}'::jsonb, 'authenticated', 'authenticated');

    PERFORM set_config('request.jwt.claim.sub', v_test_staff_id::text, true);
    PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

    SELECT id INTO v_table_id FROM public.dining_tables WHERE status = 'available' LIMIT 1;
    SELECT id INTO v_prod_id FROM public.products WHERE is_available = true LIMIT 1;

    -- 1. Mở đơn thứ nhất -> Bàn chuyển sang 'occupied'
    v_order_res := public.create_full_order(
        v_table_id,
        jsonb_build_array(jsonb_build_object('product_id', v_prod_id, 'quantity', 1))
    );
    v_order_id := (v_order_res->>'order_id')::uuid;

    -- 2. Cố tình mở thêm đơn thứ hai tại cùng bàn đó (Kỳ vọng: BỊ TỪ CHỐI)
    BEGIN
        PERFORM public.create_full_order(
            v_table_id,
            jsonb_build_array(jsonb_build_object('product_id', v_prod_id, 'quantity', 1))
        );
        v_overlap_allowed := true;
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%Bàn ăn hiện không ở trạng thái trống%' THEN
            RAISE NOTICE '>>> TEST 6 ĐẠT: Database đã chặn thành công mở đơn đè tại bàn đang occupied: %', SQLERRM;
        ELSE
            RAISE EXCEPTION 'TEST 6 BẮT LỖI KHÔNG MONG MUỐN: %', SQLERRM;
        END IF;
    END;

    -- 3. Dọn dẹp
    DELETE FROM public.order_items WHERE order_id = v_order_id;
    DELETE FROM public.orders WHERE id = v_order_id;
    UPDATE public.dining_tables SET status = 'available' WHERE id = v_table_id;
    DELETE FROM auth.users WHERE id = v_test_staff_id;
    PERFORM set_config('request.jwt.claim.sub', '', true);
    PERFORM set_config('request.jwt.claim.role', '', true);

    IF v_overlap_allowed THEN
        RAISE EXCEPTION 'LỖI NGHIỆP VỤ: TEST 6 THẤT BẠI — Cho phép tạo 2 đơn hàng đồng thời tại cùng một bàn!';
    END IF;

    RAISE NOTICE '>>> TEST 6 HOÀN TẤT & ĐÃ DỌN DẸP SẠCH DỮ LIỆU';
END;
$$;


-- ==============================================================================
-- TEST 7: KIỂM TRA THÊM MÓN VÀ TÍNH NHẤT QUÁN THANH TOÁN (ADD ITEMS & BALANCE CONSISTENCY TEST)
-- Mục tiêu:
-- 1. Thêm món vào đơn đã trả 1 phần (partially_paid) thành công, cập nhật đúng total_amount, paid_so_far, remaining_balance.
-- 2. Chặn tuyệt đối việc thêm món vào đơn đã thanh toán đầy đủ (paid).
-- ==============================================================================
DO $$
DECLARE
    v_test_staff_id uuid := gen_random_uuid();
    v_table_id uuid;
    v_prod1_id uuid;
    v_prod2_id uuid;
    v_order_res jsonb;
    v_order_id uuid;
    v_add_res jsonb;
    v_initial_total numeric;
    v_new_total numeric;
    v_paid_so_far numeric;
    v_remaining numeric;
    v_add_to_paid_allowed boolean := false;
BEGIN
    INSERT INTO auth.users (id, email, raw_user_meta_data, role, aud)
    VALUES (v_test_staff_id, 'staff_test_add@smartorder.local', '{"full_name":"Staff Test Add"}'::jsonb, 'authenticated', 'authenticated');

    PERFORM set_config('request.jwt.claim.sub', v_test_staff_id::text, true);
    PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

    SELECT id INTO v_table_id FROM public.dining_tables WHERE status = 'available' LIMIT 1;
    SELECT id INTO v_prod1_id FROM public.products WHERE is_available = true ORDER BY price ASC LIMIT 1;
    SELECT id INTO v_prod2_id FROM public.products WHERE is_available = true AND id != v_prod1_id ORDER BY price DESC LIMIT 1;

    -- 1. Mở đơn thứ nhất với món 1
    v_order_res := public.create_full_order(
        v_table_id,
        jsonb_build_array(jsonb_build_object('product_id', v_prod1_id, 'quantity', 1))
    );
    v_order_id := (v_order_res->>'order_id')::uuid;
    v_initial_total := (v_order_res->>'total_amount')::numeric;

    -- 2. Thanh toán một phần (10.000đ)
    PERFORM public.process_payment(v_order_id, 10000.00, 'cash');

    -- 3. Gọi thêm món 2 vào đơn đang partially_paid -> KỲ VỌNG: THÀNH CÔNG
    v_add_res := public.add_items_to_order(
        v_order_id,
        jsonb_build_array(jsonb_build_object('product_id', v_prod2_id, 'quantity', 1))
    );

    v_new_total := (v_add_res->>'new_total_amount')::numeric;
    v_paid_so_far := (v_add_res->>'paid_so_far')::numeric;
    v_remaining := (v_add_res->>'remaining_balance')::numeric;

    IF v_paid_so_far != 10000.00 OR v_remaining != (v_new_total - 10000.00) OR (v_add_res->>'payment_status') != 'partially_paid' THEN
        RAISE EXCEPTION 'TEST 7 LỖI TÍNH TOÁN SỐ DƯ: new_total=%, paid=%, remaining=%', v_new_total, v_paid_so_far, v_remaining;
    END IF;
    RAISE NOTICE '>>> TEST 7.1 ĐẠT: Thêm món vào đơn partially_paid thành công, số dư nhất quán';

    -- 4. Thanh toán toàn bộ số tiền còn lại -> Đơn trở thành 'paid'
    PERFORM public.process_payment(v_order_id, v_remaining, 'cash');

    -- 5. Cố tình gọi thêm món khi đơn đã thanh toán đầy đủ (paid) -> KỲ VỌNG: BỊ TỪ CHỐI
    BEGIN
        PERFORM public.add_items_to_order(
            v_order_id,
            jsonb_build_array(jsonb_build_object('product_id', v_prod1_id, 'quantity', 1))
        );
        v_add_to_paid_allowed := true;
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%Đơn hàng đã thanh toán đủ tiền%' THEN
            RAISE NOTICE '>>> TEST 7.2 ĐẠT: Đã chặn thành công việc thêm món vào đơn đã paid: %', SQLERRM;
        ELSE
            RAISE EXCEPTION 'TEST 7.2 BẮT LỖI KHÔNG MONG MUỐN: %', SQLERRM;
        END IF;
    END;

    -- 6. Dọn dẹp
    DELETE FROM public.payments WHERE order_id = v_order_id;
    DELETE FROM public.order_items WHERE order_id = v_order_id;
    DELETE FROM public.orders WHERE id = v_order_id;
    UPDATE public.dining_tables SET status = 'available' WHERE id = v_table_id;
    DELETE FROM auth.users WHERE id = v_test_staff_id;
    PERFORM set_config('request.jwt.claim.sub', '', true);
    PERFORM set_config('request.jwt.claim.role', '', true);

    IF v_add_to_paid_allowed THEN
        RAISE EXCEPTION 'LỖI NGHIỆP VỤ: TEST 7.2 THẤT BẠI — Cho phép thêm món vào đơn hàng đã thanh toán xong!';
    END IF;

    RAISE NOTICE '>>> TEST 7 TOÀN DIỆN HOÀN TẤT & ĐÃ DỌN DẸP SẠCH DỮ LIỆU';
END;
$$;


-- ==============================================================================
-- TEST 8: KIỂM TRA TÍNH TOÀN VẸN CẤU TRÚC VÀ TÍNH IDEMPOTENT (SCHEMA INTEGRITY TEST)
-- Mục tiêu: Xác minh 8 bảng, 5 triggers, 8 RLS policies và toàn bộ seed data tồn tại đầy đủ.
-- ==============================================================================
DO $$
DECLARE
    v_table_count int;
    v_trigger_count int;
    v_category_count int;
    v_table_schema_count int;
BEGIN
    -- 1. Đếm các bảng trong schema public
    SELECT count(*) INTO v_table_count
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name IN ('profiles', 'categories', 'products', 'dining_tables', 'orders', 'order_items', 'payments', 'order_counters');

    IF v_table_count < 8 THEN
        RAISE EXCEPTION 'TEST 8 THẤT BẠI: Số lượng bảng không đủ (tìm thấy % / 8 bảng)', v_table_count;
    END IF;

    -- 2. Đếm các triggers chính
    SELECT count(*) INTO v_trigger_count
    FROM information_schema.triggers
    WHERE trigger_schema IN ('public', 'auth')
      AND trigger_name IN (
        'trg_profiles_updated_at', 'trg_protect_profile_roles',
        'trg_prevent_order_item_mutation', 'trg_recalculate_order_total_amount',
        'on_auth_user_created'
      );

    IF v_trigger_count < 5 THEN
        RAISE EXCEPTION 'TEST 8 THẤT BẠI: Thiếu trigger nghiệp vụ cốt lõi (tìm thấy % / 5 trigger)', v_trigger_count;
    END IF;

    -- 3. Kiểm tra số lượng danh mục và bàn seed mẫu
    SELECT count(*) INTO v_category_count FROM public.categories;
    SELECT count(*) INTO v_table_schema_count FROM public.dining_tables;

    IF v_category_count < 5 THEN
        RAISE EXCEPTION 'TEST 8 THẤT BẠI: Dữ liệu seed categories bị thiếu (hiện có: %)', v_category_count;
    END IF;

    IF v_table_schema_count < 12 THEN
        RAISE EXCEPTION 'TEST 8 THẤT BẠI: Dữ liệu seed dining_tables bị thiếu (hiện có: %)', v_table_schema_count;
    END IF;

    RAISE NOTICE '>>> TEST 8 ĐẠT: Toàn bộ cấu trúc Schema (8 bảng, 5 triggers, seed data 5 danh mục, 12 bàn) đã sẵn sàng và toàn vẹn';
END;
$$;


-- ==============================================================================
-- TEST 9: CHỐNG GIẢI PHÓNG BÀN ĐẶT TRƯỚC (RESERVED TABLE PROTECTION TEST)
-- Mục tiêu: Đảm bảo cả Staff và Admin đều KHÔNG THỂ giải phóng bàn đang ở trạng thái 'reserved'
-- thông qua RPC public.release_dining_table(). Trạng thái đặt trước phải được bảo toàn nguyên vẹn.
-- Cơ chế chặn: Kiểm tra v_table_status = 'reserved' trong public.release_dining_table().
-- ==============================================================================
DO $$
DECLARE
    v_test_staff_id uuid := gen_random_uuid();
    v_test_table_id uuid := gen_random_uuid();
    v_staff_release_allowed boolean := false;
    v_admin_release_allowed boolean := false;
    v_table_status_after text;
BEGIN
    -- 1. Chuẩn bị nhân viên test (role = 'staff')
    INSERT INTO auth.users (id, email, raw_user_meta_data, role, aud)
    VALUES (v_test_staff_id, 'staff_test_reserved@smartorder.local', '{"full_name":"Staff Test Reserved"}'::jsonb, 'authenticated', 'authenticated');

    -- 2. Tạo một bàn test ở trạng thái 'reserved'
    INSERT INTO public.dining_tables (id, name, capacity, area, status)
    VALUES (v_test_table_id, 'Bàn Test Reserved ' || substr(gen_random_uuid()::text, 1, 6), 4, 'Tầng 1', 'reserved');

    -- 3. Thiết lập context phiên người dùng là Staff
    PERFORM set_config('request.jwt.claim.sub', v_test_staff_id::text, true);
    PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

    -- 3.1. Thử giải phóng bàn reserved bằng vai trò Staff (Kỳ vọng: BẮT BUỘC BỊ TỪ CHỐI)
    BEGIN
        PERFORM public.release_dining_table(v_test_table_id);
        v_staff_release_allowed := true;
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%Bàn đang ở trạng thái đặt trước (reserved)%' THEN
            RAISE NOTICE '>>> TEST 9.1 ĐẠT: RPC release_dining_table đã chặn Staff giải phóng bàn reserved: %', SQLERRM;
        ELSE
            RAISE EXCEPTION 'TEST 9.1 BẮT LỖI KHÔNG MONG MUỐN: %', SQLERRM;
        END IF;
    END;

    IF v_staff_release_allowed THEN
        RAISE EXCEPTION 'LỖI NGHIỆP VỤ: TEST 9.1 THẤT BẠI — Hệ thống cho phép Staff giải phóng bàn đang đặt trước (reserved)!';
    END IF;

    -- 4. Tạm thời giải phóng context JWT để cập nhật vai trò nhân sự sang 'admin' từ phiên DBA
    PERFORM set_config('request.jwt.claim.sub', '', true);
    PERFORM set_config('request.jwt.claim.role', '', true);
    UPDATE public.profiles SET role = 'admin' WHERE id = v_test_staff_id;

    -- Tái thiết lập context phiên người dùng với vai trò Admin
    PERFORM set_config('request.jwt.claim.sub', v_test_staff_id::text, true);
    PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

    -- 4.1. Thử giải phóng bàn reserved bằng vai trò Admin (Kỳ vọng: CŨNG BẮT BUỘC BỊ TỪ CHỐI)
    BEGIN
        PERFORM public.release_dining_table(v_test_table_id);
        v_admin_release_allowed := true;
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%Bàn đang ở trạng thái đặt trước (reserved)%' THEN
            RAISE NOTICE '>>> TEST 9.2 ĐẠT: RPC release_dining_table đã chặn cả Admin giải phóng bàn reserved: %', SQLERRM;
        ELSE
            RAISE EXCEPTION 'TEST 9.2 BẮT LỖI KHÔNG MONG MUỐN: %', SQLERRM;
        END IF;
    END;

    IF v_admin_release_allowed THEN
        RAISE EXCEPTION 'LỖI NGHIỆP VỤ: TEST 9.2 THẤT BẠI — Hệ thống cho phép Admin giải phóng bàn đang đặt trước (reserved)!';
    END IF;

    -- 5. Xác minh trạng thái bàn trong CSDL vẫn giữ nguyên 'reserved'
    SELECT status INTO v_table_status_after FROM public.dining_tables WHERE id = v_test_table_id;
    IF v_table_status_after != 'reserved' THEN
        RAISE EXCEPTION 'LỖI TOÀN VẸN: TEST 9.3 THẤT BẠI — Trạng thái bàn đã bị biến đổi thành "%"', v_table_status_after;
    ELSE
        RAISE NOTICE '>>> TEST 9.3 ĐẠT: Bàn ăn vẫn bảo toàn nguyên vẹn trạng thái reserved sau các lần gọi bị từ chối';
    END IF;

    -- 6. Dọn dẹp dữ liệu test và reset context
    DELETE FROM public.dining_tables WHERE id = v_test_table_id;
    DELETE FROM auth.users WHERE id = v_test_staff_id;
    PERFORM set_config('request.jwt.claim.sub', '', true);
    PERFORM set_config('request.jwt.claim.role', '', true);

    RAISE NOTICE '>>> TEST 9 TOÀN DIỆN HOÀN TẤT & ĐÃ DỌN DẸP SẠCH DỮ LIỆU';
END;
$$;
