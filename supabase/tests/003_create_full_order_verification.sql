-- ==============================================================================
-- SMART ORDER — DEDICATED TEST SUITE FOR RPC public.create_full_order()
-- Test File: supabase/tests/003_create_full_order_verification.sql
-- Database: PostgreSQL 15+ (Supabase)
-- Phase: C2.4 Hardened Test — RPC Verification & Order Creation Security
-- ==============================================================================
-- CẢNH BÁO BẢO MẬT & NGUYÊN TẮC KIỂM THỬ:
-- 1. File này là kịch bản kiểm thử tĩnh được thiết kế dựa trên mã nguồn thực tế
--    tại supabase/migrations/001_initial_schema.sql.
-- 2. CHƯA được thực thi trên môi trường PostgreSQL / Supabase thật. Tuyệt đối không
--    tuyên bố các kịch bản đã "ĐẠT" trên môi trường thực tế khi chưa chạy script này.
-- 3. Script KHÔNG chạm vào bất kỳ dữ liệu khách hàng, bàn ăn hay đơn hàng thật nào.
--    Mọi dữ liệu kiểm thử (fixtures) đều sinh ngẫu nhiên (UUIDv4) và được hoàn tác sạch sẽ.
--
-- HƯỚNG DẪN THỰC THI TRÊN SUPABASE DASHBOARD:
-- 1. Mở Supabase Dashboard -> Truy cập mục SQL Editor -> Mở tab truy vấn mới.
-- 2. Chọn TOÀN BỘ nội dung file (Ctrl+A) và nhấn "Run" trong MỘT LẦN CHẠY DUY NHẤT.
-- 3. Quan sát tab Results:
--    - Bảng 1: Bảng tổng kết ("Số kịch bản đạt", "Tổng số kịch bản bắt buộc", "Trạng thái tổng thể", "Chẩn đoán tiến trình").
--    - Bảng 2: Danh sách chi tiết từng kịch bản và lý do đạt/thất bại.
-- 4. Quan sát tab Messages: Theo dõi thông báo hoàn tác dữ liệu và log từng bước.
--
-- GIẢI THÍCH VỀ CƠ CHẾ TRANSACTION ROLLBACK & PHẠM VI PG_TEMP:
-- 1. TẠI SAO PHẢI CHẠY TOÀN BỘ FILE TRONG MỘT LẦN CHẠY?
--    - Bảng báo cáo kết quả được lưu trữ tạm thời trong schema `pg_temp`.
--    - `pg_temp` gắn liền với phiên kết nối backend. Nếu chạy từng câu lệnh riêng lẻ
--      qua Connection Pooler (PgBouncer trong chế độ transaction pooling), các lệnh
--      có thể rơi vào các kết nối khác nhau và bảng tạm sẽ không tìm thấy.
--
-- 2. CƠ CHẾ HOÀN TÁC DỮ LIỆU BẰNG ENGINE-LEVEL SUBTRANSACTION ROLLBACK:
--    - Mọi thao tác chèn fixture (auth.users, categories, products, dining_tables, orders)
--      và gọi RPC diễn ra bên trong một tiểu khối PL/pgSQL (subtransaction).
--    - Khi hoàn thành 11 kịch bản kiểm thử, tiểu khối chủ động phát sinh ngoại lệ nội bộ
--      `TEST_SUITE_FORCE_ROLLBACK` để engine PostgreSQL hoàn tác (ROLLBACK) 100% thay đổi
--      trên các bảng vật lý.
--    - Biến bộ nhớ PL/pgSQL (`v_report`) không bị ảnh hưởng bởi rollback của engine,
--      cho phép nạp đầy đủ kết quả vào bảng tạm `pg_temp.order_test_report` sau khi hoàn tác.
--    - GHI CHÚ MINH BẠCH: Cơ chế này hoàn tác sạch sẽ ở cấp độ engine trong phiên hoạt động
--      bình thường, nhưng không thể bảo đảm 100% nếu server gặp sự cố phần cứng/mất điện
--      đột ngột trước khi kết thúc khối lệnh.
--
-- 3. GIỚI HẠN CỦA VIỆC MÔ PHỎNG JWT BẰNG SET_CONFIG:
--    - `set_config('request.jwt.claim.sub', ...)` chỉ cung cấp ngữ cảnh định danh người gọi
--      cho hàm `auth.uid()` bên trong hàm SECURITY DEFINER của PostgreSQL.
--    - Kỹ thuật này KHÔNG kiểm tra được:
--      + Tính hợp lệ của chữ ký mật mã JWT (HMAC-SHA256/RSA) và thời hạn token (exp).
--      + Tầng Kong API Gateway (Rate limiting, CORS, xác thực API Key).
--      + Tầng PostgREST Web Server (Reload schema cache, map role qua HTTP Authorization Header).
--    - Cần có bài kiểm thử tích hợp (Integration Test) qua Supabase Client SDK với token thật
--      để kiểm chứng toàn diện luồng người dùng từ giao diện Flutter.
-- ==============================================================================

-- BƯỚC A: KHỞI TẠO BẢNG TẠM BÁO CÁO (CHỈ TỒN TẠI TRONG PHIÊN THỰC THI HIỆN TẠI)
CREATE TEMP TABLE IF NOT EXISTS pg_temp.order_test_report (
    scenario_id int PRIMARY KEY,
    scenario_name text NOT NULL,
    status text NOT NULL,
    details text NOT NULL
);
TRUNCATE pg_temp.order_test_report;


-- BƯỚC B: THỰC THI KIỂM THỬ TRONG SUBTRANSACTION VÀ TỰ ĐỘNG ROLLBACK FIXTURE
DO $$
DECLARE
    -- Định danh tài khoản kiểm thử ngẫu nhiên
    v_staff_id uuid := gen_random_uuid();
    v_admin_id uuid := gen_random_uuid();
    v_kitchen_id uuid := gen_random_uuid();
    v_inactive_id uuid := gen_random_uuid();
    v_staff_email text := 'staff_ord_test_' || substr(gen_random_uuid()::text, 1, 8) || '@smartorder.test';
    v_admin_email text := 'admin_ord_test_' || substr(gen_random_uuid()::text, 1, 8) || '@smartorder.test';
    v_kitchen_email text := 'kitchen_ord_test_' || substr(gen_random_uuid()::text, 1, 8) || '@smartorder.test';
    v_inactive_email text := 'inactive_ord_test_' || substr(gen_random_uuid()::text, 1, 8) || '@smartorder.test';

    -- Định danh danh mục và sản phẩm kiểm thử ngẫu nhiên
    v_category_id uuid := gen_random_uuid();
    v_prod_avail_1_id uuid := gen_random_uuid();
    v_prod_avail_2_id uuid := gen_random_uuid();
    v_prod_unavail_id uuid := gen_random_uuid();
    v_non_existent_prod_id uuid := gen_random_uuid();

    -- Định danh bàn ăn kiểm thử ngẫu nhiên
    v_table_avail_1_id uuid := gen_random_uuid();
    v_table_avail_tamper_id uuid := gen_random_uuid();
    v_table_with_order_id uuid := gen_random_uuid();
    v_table_occupied_id uuid := gen_random_uuid();
    v_table_reserved_id uuid := gen_random_uuid();
    v_table_general_id uuid := gen_random_uuid();
    v_non_existent_table_id uuid := gen_random_uuid();

    -- Định danh đơn hàng có sẵn (tiền điều kiện)
    v_preexisting_order_id uuid := gen_random_uuid();
    v_test_order_code text := 'TEST-ORD-' || substr(gen_random_uuid()::text, 1, 8);

    -- Cấu trúc danh sách món JSON đầu vào
    v_valid_items jsonb;
    v_res_valid jsonb;
    v_res_tamper jsonb;

    -- Biến theo dõi kết quả trong bộ nhớ phiên PL/pgSQL
    v_report jsonb := '[]'::jsonb;
    v_passed boolean;
    v_detail text;
    v_sub_err text;

    -- Biến kiểm tra đối soát dữ liệu cơ sở dữ liệu
    v_check_table_status text;
    v_check_order_status text;
    v_check_pay_status text;
    v_check_order_total numeric(12, 2);
    v_check_items_count int;
    v_check_unit_price numeric(12, 2);
    v_check_subtotal numeric(12, 2);

    -- Quyền trên catalog
    v_anon_has_priv boolean;
    v_auth_has_priv boolean;

    -- Quản lý hoàn tác
    v_item jsonb;
    v_rollback_err text;
BEGIN
    RAISE NOTICE '====================================================================';
    RAISE NOTICE 'BẮT ĐẦU KIỂM THỬ TOÀN DIỆN RPC public.create_full_order()';
    RAISE NOTICE '====================================================================';

    -- --------------------------------------------------------------------------
    -- BƯỚC 1: TIỂU KHỐI TRANSACTION TỰ HOÀN TÁC (AUTO-ROLLBACK SUBTRANSACTION)
    -- Dữ liệu fixture chỉ tồn tại tạm thời bên trong tiểu khối này.
    -- Khi kết thúc kiểm thử, tiểu khối chủ động phát sinh ngoại lệ TEST_SUITE_FORCE_ROLLBACK
    -- để engine PostgreSQL hoàn tác 100% dữ liệu đã ghi vào các bảng vật lý.
    -- --------------------------------------------------------------------------
    BEGIN
        -- Làm sạch cấu hình phiên GUC
        PERFORM set_config('request.jwt.claim.sub', '', true);
        PERFORM set_config('request.jwt.claim.role', '', true);

        -- 1.1. Tạo 4 tài khoản trong auth.users (Trigger on_auth_user_created tự tạo profiles role = 'staff')
        INSERT INTO auth.users (id, email, raw_user_meta_data, role, aud)
        VALUES
            (v_staff_id, v_staff_email, '{"full_name":"Test Staff Order Runner"}'::jsonb, 'authenticated', 'authenticated'),
            (v_admin_id, v_admin_email, '{"full_name":"Test Admin Order Runner"}'::jsonb, 'authenticated', 'authenticated'),
            (v_kitchen_id, v_kitchen_email, '{"full_name":"Test Kitchen Order Runner"}'::jsonb, 'authenticated', 'authenticated'),
            (v_inactive_id, v_inactive_email, '{"full_name":"Test Inactive User Runner"}'::jsonb, 'authenticated', 'authenticated');

        -- 1.2. Điều chỉnh vai trò và trạng thái hồ sơ từ phiên DBA (session_user = postgres/supabase_admin)
        UPDATE public.profiles SET role = 'admin' WHERE id = v_admin_id;
        UPDATE public.profiles SET role = 'kitchen' WHERE id = v_kitchen_id;
        UPDATE public.profiles SET is_active = false WHERE id = v_inactive_id;

        -- 1.3. Tạo danh mục thực đơn và sản phẩm kiểm thử
        INSERT INTO public.categories (id, name, display_order, is_active)
        VALUES (v_category_id, 'TEST_CAT_' || substr(gen_random_uuid()::text, 1, 8), 1, true);

        INSERT INTO public.products (id, category_id, name, price, station, is_available)
        VALUES
            (v_prod_avail_1_id, v_category_id, 'TEST_MON_PHO_' || substr(gen_random_uuid()::text, 1, 6), 55000.00, 'kitchen', true),
            (v_prod_avail_2_id, v_category_id, 'TEST_MON_TRA_' || substr(gen_random_uuid()::text, 1, 6), 25000.00, 'bar', true),
            (v_prod_unavail_id, v_category_id, 'TEST_MON_HET_' || substr(gen_random_uuid()::text, 1, 6), 40000.00, 'kitchen', false);

        -- 1.4. Tạo các bàn ăn kiểm thử đại diện cho các trạng thái nghiệp vụ
        INSERT INTO public.dining_tables (id, name, capacity, area, status)
        VALUES
            (v_table_avail_1_id, 'TEST_TBL_AV1_' || substr(gen_random_uuid()::text, 1, 6), 4, 'Khu Test', 'available'),
            (v_table_avail_tamper_id, 'TEST_TBL_AVT_' || substr(gen_random_uuid()::text, 1, 6), 4, 'Khu Test', 'available'),
            (v_table_with_order_id, 'TEST_TBL_ACT_' || substr(gen_random_uuid()::text, 1, 6), 4, 'Khu Test', 'available'),
            (v_table_occupied_id, 'TEST_TBL_OCC_' || substr(gen_random_uuid()::text, 1, 6), 4, 'Khu Test', 'occupied'),
            (v_table_reserved_id, 'TEST_TBL_RSV_' || substr(gen_random_uuid()::text, 1, 6), 4, 'Khu Test', 'reserved'),
            (v_table_general_id, 'TEST_TBL_GEN_' || substr(gen_random_uuid()::text, 1, 6), 4, 'Khu Test', 'available');

        -- 1.5. Tạo 1 đơn hàng kiểm thử chưa hoàn tất (pending) gắn với bàn v_table_with_order_id
        INSERT INTO public.orders (id, order_code, table_id, staff_id, status, payment_status, total_amount)
        VALUES (
            v_preexisting_order_id,
            v_test_order_code,
            v_table_with_order_id,
            v_staff_id,
            'pending',
            'unpaid',
            0.00
        );

        -- 1.6. Chuẩn bị mảng món hợp lệ mẫu: 2 suất món 1 (55k * 2) + 1 suất món 2 (25k * 1) = 135,000đ
        v_valid_items := jsonb_build_array(
            jsonb_build_object(
                'product_id', v_prod_avail_1_id,
                'quantity', 2,
                'notes', 'Ít hành'
            ),
            jsonb_build_object(
                'product_id', v_prod_avail_2_id,
                'quantity', 1,
                'notes', 'Ít đá'
            )
        );


        -- ----------------------------------------------------------------------
        -- KỊCH BẢN 1: CHẶN NGƯỜI DÙNG CHƯA ĐĂNG NHẬP (auth.uid() IS NULL)
        -- ----------------------------------------------------------------------
        v_passed := false;
        v_detail := '';
        PERFORM set_config('request.jwt.claim.sub', '', true);
        PERFORM set_config('request.jwt.claim.role', '', true);

        BEGIN
            PERFORM public.create_full_order(v_table_general_id, v_valid_items);
            v_passed := false;
            v_detail := 'Lỗ hổng: RPC cho phép người dùng chưa xác thực (auth.uid() IS NULL) gọi hàm tạo đơn';
        EXCEPTION WHEN OTHERS THEN
            IF SQLERRM LIKE '%Yêu cầu xác thực: Người dùng chưa đăng nhập hệ thống%' THEN
                v_passed := true;
                v_detail := 'Đã từ chối unauthenticated caller với thông báo xác thực chuẩn';
            ELSE
                v_passed := false;
                v_detail := 'Bắt lỗi sai thông điệp mong đợi: ' || SQLERRM;
            END IF;
        END;

        v_report := v_report || jsonb_build_object(
            'scenario_id', 1,
            'scenario_name', 'Xác thực người dùng: Chặn caller chưa đăng nhập',
            'status', CASE WHEN v_passed THEN 'ĐẠT' ELSE 'THẤT BẠI' END,
            'details', v_detail
        );


        -- ----------------------------------------------------------------------
        -- KỊCH BẢN 2: CHẶN TÀI KHOẢN BỊ VÔ HIỆU HÓA (is_active = false)
        -- ----------------------------------------------------------------------
        v_passed := false;
        v_detail := '';
        PERFORM set_config('request.jwt.claim.sub', v_inactive_id::text, true);
        PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

        BEGIN
            PERFORM public.create_full_order(v_table_general_id, v_valid_items);
            v_passed := false;
            v_detail := 'Lỗ hổng: Cho phép tài khoản bị vô hiệu hóa (is_active = false) tạo đơn';
        EXCEPTION WHEN OTHERS THEN
            IF SQLERRM LIKE '%Hồ sơ người dùng không tồn tại hoặc tài khoản đã bị vô hiệu hóa%' THEN
                v_passed := true;
                v_detail := 'Đã từ chối tài khoản is_active = false đúng quy tắc an toàn';
            ELSE
                v_passed := false;
                v_detail := 'Bắt lỗi sai thông điệp mong đợi: ' || SQLERRM;
            END IF;
        END;

        v_report := v_report || jsonb_build_object(
            'scenario_id', 2,
            'scenario_name', 'Trạng thái tài khoản: Chặn tài khoản bị vô hiệu hóa',
            'status', CASE WHEN v_passed THEN 'ĐẠT' ELSE 'THẤT BẠI' END,
            'details', v_detail
        );


        -- ----------------------------------------------------------------------
        -- KỊCH BẢN 3: PHÂN QUYỀN VAI TRÒ RBAC (CHẶN ROLE KHÔNG HỢP LỆ NHƯ KITCHEN)
        -- ----------------------------------------------------------------------
        v_passed := false;
        v_detail := '';
        PERFORM set_config('request.jwt.claim.sub', v_kitchen_id::text, true);
        PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

        BEGIN
            PERFORM public.create_full_order(v_table_general_id, v_valid_items);
            v_passed := false;
            v_detail := 'Lỗ hổng: Cho phép vai trò không được phân quyền (kitchen) tạo đơn hàng';
        EXCEPTION WHEN OTHERS THEN
            IF SQLERRM LIKE '%Quyền hạn không hợp lệ: Chỉ Quản trị viên hoặc Nhân viên phục vụ mới được phép tạo đơn%' THEN
                v_passed := true;
                v_detail := 'Đã chặn vai trò kitchen gọi hàm tạo đơn theo đúng ma trận RBAC';
            ELSE
                v_passed := false;
                v_detail := 'Bắt lỗi sai thông điệp mong đợi: ' || SQLERRM;
            END IF;
        END;

        v_report := v_report || jsonb_build_object(
            'scenario_id', 3,
            'scenario_name', 'Phân quyền RBAC: Chặn vai trò không có quyền mở đơn',
            'status', CASE WHEN v_passed THEN 'ĐẠT' ELSE 'THẤT BẠI' END,
            'details', v_detail
        );


        -- ----------------------------------------------------------------------
        -- KỊCH BẢN 4: TẠO ĐƠN HỢP LỆ VỚI BÀN TRỐNG VÀ SẢN PHẨM KHẢ DỤNG
        -- ----------------------------------------------------------------------
        v_passed := false;
        v_detail := '';
        PERFORM set_config('request.jwt.claim.sub', v_staff_id::text, true);
        PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

        BEGIN
            v_res_valid := public.create_full_order(v_table_avail_1_id, v_valid_items, 'Ghi chú bàn 1');

            -- 4.1. Kiểm tra JSON kết quả trả về
            IF (v_res_valid->>'success')::boolean IS TRUE
               AND v_res_valid->>'order_id' IS NOT NULL
               AND (v_res_valid->>'table_id')::uuid = v_table_avail_1_id
               AND (v_res_valid->>'total_amount')::numeric = 135000.00
               AND v_res_valid->>'status' = 'pending'
               AND v_res_valid->>'payment_status' = 'unpaid'
               AND (v_res_valid->>'item_count')::int = 2
            THEN
                -- 4.2. Kiểm tra trạng thái bàn ăn đã chuyển sang 'occupied'
                SELECT status INTO v_check_table_status
                FROM public.dining_tables
                WHERE id = v_table_avail_1_id;

                -- 4.3. Kiểm tra bản ghi orders trong cơ sở dữ liệu
                SELECT status, payment_status, total_amount
                INTO v_check_order_status, v_check_pay_status, v_check_order_total
                FROM public.orders
                WHERE id = (v_res_valid->>'order_id')::uuid;

                -- 4.4. Kiểm tra bản ghi order_items trong cơ sở dữ liệu
                SELECT count(*) INTO v_check_items_count
                FROM public.order_items
                WHERE order_id = (v_res_valid->>'order_id')::uuid;

                IF v_check_table_status = 'occupied'
                   AND v_check_order_status = 'pending'
                   AND v_check_pay_status = 'unpaid'
                   AND v_check_order_total = 135000.00
                   AND v_check_items_count = 2
                THEN
                    v_passed := true;
                    v_detail := 'Tạo đơn thành công: JSON hợp lệ, bàn đổi sang occupied, orders status pending, total_amount=135,000đ, 2 bản ghi order_items';
                ELSE
                    v_passed := false;
                    v_detail := 'Bất nhất dữ liệu DB: table_status=' || COALESCE(v_check_table_status, 'NULL') ||
                                ', order_status=' || COALESCE(v_check_order_status, 'NULL') ||
                                ', total_amount=' || COALESCE(v_check_order_total::text, 'NULL') ||
                                ', items_count=' || COALESCE(v_check_items_count::text, 'NULL');
                END IF;
            ELSE
                v_passed := false;
                v_detail := 'JSON phản hồi từ RPC không đạt cấu trúc kỳ vọng: ' || v_res_valid::text;
            END IF;
        EXCEPTION WHEN OTHERS THEN
            v_passed := false;
            v_detail := 'Lỗi bất ngờ khi gọi create_full_order hợp lệ: ' || SQLERRM;
        END;

        v_report := v_report || jsonb_build_object(
            'scenario_id', 4,
            'scenario_name', 'Tạo đơn hợp lệ: Bàn trống, món khả dụng, cập nhật trạng thái chuẩn',
            'status', CASE WHEN v_passed THEN 'ĐẠT' ELSE 'THẤT BẠI' END,
            'details', v_detail
        );


        -- ----------------------------------------------------------------------
        -- KỊCH BẢN 5: CHẶN TẠO ĐƠN CHỒNG CHÉO TRÊN BÀN ĐANG CÓ ĐƠN HOẠT ĐỘNG
        -- ----------------------------------------------------------------------
        v_passed := false;
        v_detail := '';
        PERFORM set_config('request.jwt.claim.sub', v_staff_id::text, true);
        PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

        BEGIN
            PERFORM public.create_full_order(v_table_with_order_id, v_valid_items);
            v_passed := false;
            v_detail := 'Lỗ hổng: RPC cho phép mở thêm đơn mới trên bàn đang có đơn pending chưa hoàn tất';
        EXCEPTION WHEN OTHERS THEN
            IF SQLERRM LIKE '%Bàn ăn hiện đang có đơn hàng chưa hoàn tất%' THEN
                v_passed := true;
                v_detail := 'Đã chặn tạo đơn chồng chéo khi bàn còn đơn pending hoạt động';
            ELSE
                v_passed := false;
                v_detail := 'Bắt lỗi sai thông điệp mong đợi: ' || SQLERRM;
            END IF;
        END;

        v_report := v_report || jsonb_build_object(
            'scenario_id', 5,
            'scenario_name', 'Chống đơn chồng chéo: Chặn mở đơn trên bàn có đơn chưa hoàn tất',
            'status', CASE WHEN v_passed THEN 'ĐẠT' ELSE 'THẤT BẠI' END,
            'details', v_detail
        );


        -- ----------------------------------------------------------------------
        -- KỊCH BẢN 6: CHẶN MỞ ĐƠN TRÊN BÀN KHÔNG KHẢ DỤNG (RESERVED / OCCUPIED / KHÔNG TỒN TẠI)
        -- ----------------------------------------------------------------------
        v_passed := false;
        v_detail := '';
        PERFORM set_config('request.jwt.claim.sub', v_staff_id::text, true);
        PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

        -- 6.1. Bàn đặt trước (reserved)
        BEGIN
            PERFORM public.create_full_order(v_table_reserved_id, v_valid_items);
            v_passed := false;
            v_detail := 'Lỗ hổng: Không chặn mở đơn trên bàn reserved';
        EXCEPTION WHEN OTHERS THEN
            IF SQLERRM LIKE '%Bàn đang ở trạng thái đặt trước (reserved)%' THEN
                -- 6.2. Bàn đang có khách (occupied)
                BEGIN
                    PERFORM public.create_full_order(v_table_occupied_id, v_valid_items);
                    v_passed := false;
                    v_detail := 'Lỗ hổng: Không chặn mở đơn trên bàn occupied';
                EXCEPTION WHEN OTHERS THEN
                    IF SQLERRM LIKE '%Không thể mở đơn mới: Bàn ăn hiện không ở trạng thái trống%' THEN
                        -- 6.3. Bàn không tồn tại
                        BEGIN
                            PERFORM public.create_full_order(v_non_existent_table_id, v_valid_items);
                            v_passed := false;
                            v_detail := 'Lỗ hổng: Không kiểm tra bàn không tồn tại';
                        EXCEPTION WHEN OTHERS THEN
                            IF SQLERRM LIKE '%Bàn ăn không tồn tại trong hệ thống%' THEN
                                v_passed := true;
                                v_detail := 'Đã chặn toàn diện bàn reserved, occupied và bàn không tồn tại';
                            ELSE
                                v_passed := false;
                                v_detail := 'Bàn không tồn tại trả về lỗi sai: ' || SQLERRM;
                            END IF;
                        END;
                    ELSE
                        v_passed := false;
                        v_detail := 'Bàn occupied trả về lỗi sai: ' || SQLERRM;
                    END IF;
                END;
            ELSE
                v_passed := false;
                v_detail := 'Bàn reserved trả về lỗi sai: ' || SQLERRM;
            END IF;
        END;

        v_report := v_report || jsonb_build_object(
            'scenario_id', 6,
            'scenario_name', 'Kiểm soát trạng thái bàn: Chặn bàn reserved, occupied và bàn rác',
            'status', CASE WHEN v_passed THEN 'ĐẠT' ELSE 'THẤT BẠI' END,
            'details', v_detail
        );


        -- ----------------------------------------------------------------------
        -- KỊCH BẢN 7: CHẶN ĐẶT MÓN KHI SẢN PHẨM TẠM NGƯNG PHỤC VỤ (is_available = false)
        -- ----------------------------------------------------------------------
        v_passed := false;
        v_detail := '';
        PERFORM set_config('request.jwt.claim.sub', v_staff_id::text, true);
        PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

        BEGIN
            PERFORM public.create_full_order(
                v_table_general_id,
                jsonb_build_array(
                    jsonb_build_object('product_id', v_prod_unavail_id, 'quantity', 1)
                )
            );
            v_passed := false;
            v_detail := 'Lỗ hổng: RPC cho phép đặt món đã bị đánh dấu tạm ngưng phục vụ (is_available = false)';
        EXCEPTION WHEN OTHERS THEN
            IF SQLERRM LIKE '%hiện đang tạm ngưng phục vụ, không thể đặt món%' THEN
                v_passed := true;
                v_detail := 'Đã chặn đặt món tạm ngưng phục vụ với thông báo chính xác';
            ELSE
                v_passed := false;
                v_detail := 'Bắt lỗi sai thông điệp mong đợi: ' || SQLERRM;
            END IF;
        END;

        v_report := v_report || jsonb_build_object(
            'scenario_id', 7,
            'scenario_name', 'Tình trạng món: Chặn đặt sản phẩm tạm ngưng phục vụ',
            'status', CASE WHEN v_passed THEN 'ĐẠT' ELSE 'THẤT BẠI' END,
            'details', v_detail
        );


        -- ----------------------------------------------------------------------
        -- KỊCH BẢN 8: CHẶN ĐẶT MÓN KHI MÃ SẢN PHẨM KHÔNG TỒN TẠI TRONG THỰC ĐƠN
        -- ----------------------------------------------------------------------
        v_passed := false;
        v_detail := '';
        PERFORM set_config('request.jwt.claim.sub', v_staff_id::text, true);
        PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

        BEGIN
            PERFORM public.create_full_order(
                v_table_general_id,
                jsonb_build_array(
                    jsonb_build_object('product_id', v_non_existent_prod_id, 'quantity', 1)
                )
            );
            v_passed := false;
            v_detail := 'Lỗ hổng: RPC cho phép đặt mã sản phẩm không tồn tại trong thực đơn';
        EXCEPTION WHEN OTHERS THEN
            IF SQLERRM LIKE '%Mã sản phẩm không tồn tại trong thực đơn%' THEN
                v_passed := true;
                v_detail := 'Đã chặn đặt món với UUID sản phẩm không tồn tại';
            ELSE
                v_passed := false;
                v_detail := 'Bắt lỗi sai thông điệp mong đợi: ' || SQLERRM;
            END IF;
        END;

        v_report := v_report || jsonb_build_object(
            'scenario_id', 8,
            'scenario_name', 'Toàn vẹn thực đơn: Chặn đặt sản phẩm không tồn tại',
            'status', CASE WHEN v_passed THEN 'ĐẠT' ELSE 'THẤT BẠI' END,
            'details', v_detail
        );


        -- ----------------------------------------------------------------------
        -- KỊCH BẢN 9: CHỐNG THAO TÚNG GIÁ TỪ CLIENT (PRICE TAMPERING IMMUNITY)
        -- Giả lập Client cố tình gửi kèm trường 'price', 'unit_price', 'subtotal'
        -- với mức giá 100đ hòng gian lận đơn hàng.
        -- KỲ VỌNG: RPC bỏ qua hoàn toàn giá client, lấy đúng 55,000đ từ DB và tính subtotal=110,000đ.
        -- ----------------------------------------------------------------------
        v_passed := false;
        v_detail := '';
        PERFORM set_config('request.jwt.claim.sub', v_staff_id::text, true);
        PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

        BEGIN
            v_res_tamper := public.create_full_order(
                v_table_avail_tamper_id,
                jsonb_build_array(
                    jsonb_build_object(
                        'product_id', v_prod_avail_1_id,
                        'quantity', 2,
                        'price', 100.00,
                        'unit_price', 100.00,
                        'subtotal', 200.00,
                        'notes', 'Client cố tình truyền giá 100đ'
                    )
                )
            );

            -- Đối soát unit_price và subtotal trong order_items thực tế
            SELECT unit_price, subtotal
            INTO v_check_unit_price, v_check_subtotal
            FROM public.order_items
            WHERE order_id = (v_res_tamper->>'order_id')::uuid;

            -- Đối soát total_amount trong orders
            SELECT total_amount
            INTO v_check_order_total
            FROM public.orders
            WHERE id = (v_res_tamper->>'order_id')::uuid;

            IF (v_res_tamper->>'total_amount')::numeric = 110000.00
               AND v_check_unit_price = 55000.00
               AND v_check_subtotal = 110000.00
               AND v_check_order_total = 110000.00
            THEN
                v_passed := true;
                v_detail := 'An toàn tuyệt đối: Giá client gửi (100đ) bị bỏ qua, DB tự lấy giá gốc 55k, subtotal=110k, total=110k';
            ELSE
                v_passed := false;
                v_detail := 'Lỗ hổng thao túng giá: RPC chấp nhận giá client! JSON=' || (v_res_tamper->>'total_amount') ||
                            ', DB unit_price=' || COALESCE(v_check_unit_price::text, 'NULL') ||
                            ', DB subtotal=' || COALESCE(v_check_subtotal::text, 'NULL');
            END IF;
        EXCEPTION WHEN OTHERS THEN
            v_passed := false;
            v_detail := 'Lỗi bất ngờ trong kiểm thử thao túng giá: ' || SQLERRM;
        END;

        v_report := v_report || jsonb_build_object(
            'scenario_id', 9,
            'scenario_name', 'Chống gian lận tài chính: Kháng thao túng giá từ Client',
            'status', CASE WHEN v_passed THEN 'ĐẠT' ELSE 'THẤT BẠI' END,
            'details', v_detail
        );


        -- ----------------------------------------------------------------------
        -- KỊCH BẢN 10: XÁC THỰC CẤU TRÚC JSON ĐẦU VÀO VÀ SỐ LƯỢNG MÓN
        -- ----------------------------------------------------------------------
        v_passed := false;
        v_detail := '';
        PERFORM set_config('request.jwt.claim.sub', v_staff_id::text, true);
        PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

        -- 10.1. Mảng món rỗng []
        BEGIN
            PERFORM public.create_full_order(v_table_general_id, '[]'::jsonb);
            v_passed := false;
            v_detail := 'Lỗ hổng: Không chặn mảng món rỗng';
        EXCEPTION WHEN OTHERS THEN
            IF SQLERRM LIKE '%Danh sách món đặt không được để trống%' THEN
                -- 10.2. Số lượng bằng 0
                BEGIN
                    PERFORM public.create_full_order(
                        v_table_general_id,
                        jsonb_build_array(jsonb_build_object('product_id', v_prod_avail_1_id, 'quantity', 0))
                    );
                    v_passed := false;
                    v_detail := 'Lỗ hổng: Không chặn số lượng bằng 0';
                EXCEPTION WHEN OTHERS THEN
                    IF SQLERRM LIKE '%Số lượng món không hợp lệ (0)%' THEN
                        -- 10.3. Số lượng âm (-5)
                        BEGIN
                            PERFORM public.create_full_order(
                                v_table_general_id,
                                jsonb_build_array(jsonb_build_object('product_id', v_prod_avail_1_id, 'quantity', -5))
                            );
                            v_passed := false;
                            v_detail := 'Lỗ hổng: Không chặn số lượng âm';
                        EXCEPTION WHEN OTHERS THEN
                            IF SQLERRM LIKE '%Số lượng món phải là số nguyên dương hợp lệ%' THEN
                                -- 10.4. Số lượng vượt ngưỡng (>100)
                                BEGIN
                                    PERFORM public.create_full_order(
                                        v_table_general_id,
                                        jsonb_build_array(jsonb_build_object('product_id', v_prod_avail_1_id, 'quantity', 101))
                                    );
                                    v_passed := false;
                                    v_detail := 'Lỗ hổng: Không chặn số lượng > 100';
                                EXCEPTION WHEN OTHERS THEN
                                    IF SQLERRM LIKE '%Số lượng món không hợp lệ (101)%' THEN
                                        -- 10.5. Phần tử phi object (chuỗi thay vì JSON object)
                                        BEGIN
                                            PERFORM public.create_full_order(
                                                v_table_general_id,
                                                '["chuoi_khong_hop_le"]'::jsonb
                                            );
                                            v_passed := false;
                                            v_detail := 'Lỗ hổng: Không chặn phần tử phi JSON object';
                                        EXCEPTION WHEN OTHERS THEN
                                            IF SQLERRM LIKE '%Phần tử trong danh sách món phải là một JSON object hợp lệ%' THEN
                                                v_passed := true;
                                                v_detail := 'Đã chặn toàn diện mảng rỗng, qty=0, qty=-5, qty=101 và phần tử phi object';
                                            ELSE
                                                v_passed := false;
                                                v_detail := 'Phần tử phi object trả về lỗi sai: ' || SQLERRM;
                                            END IF;
                                        END;
                                    ELSE
                                        v_passed := false;
                                        v_detail := 'Số lượng > 100 trả về lỗi sai: ' || SQLERRM;
                                    END IF;
                                END;
                            ELSE
                                v_passed := false;
                                v_detail := 'Số lượng âm trả về lỗi sai: ' || SQLERRM;
                            END IF;
                        END;
                    ELSE
                        v_passed := false;
                        v_detail := 'Số lượng 0 trả về lỗi sai: ' || SQLERRM;
                    END IF;
                END;
            ELSE
                v_passed := false;
                v_detail := 'Mảng rỗng trả về lỗi sai: ' || SQLERRM;
            END IF;
        END;

        v_report := v_report || jsonb_build_object(
            'scenario_id', 10,
            'scenario_name', 'Kiểm tra tham số: Chặn mảng rỗng, số lượng sai (0, âm, >100)',
            'status', CASE WHEN v_passed THEN 'ĐẠT' ELSE 'THẤT BẠI' END,
            'details', v_detail
        );


        -- ----------------------------------------------------------------------
        -- KỊCH BẢN 11: KIỂM SOÁT PHÂN QUYỀN TRÊN CATALOG HỆ THỐNG (REVOKE ANON)
        -- ----------------------------------------------------------------------
        v_passed := false;
        v_detail := '';

        v_anon_has_priv := has_function_privilege('anon', 'public.create_full_order(uuid, jsonb, text)', 'EXECUTE');
        v_auth_has_priv := has_function_privilege('authenticated', 'public.create_full_order(uuid, jsonb, text)', 'EXECUTE');

        IF NOT v_anon_has_priv AND v_auth_has_priv THEN
            v_passed := true;
            v_detail := 'Quyền Catalog chuẩn xác: anon bị thu hồi quyền EXECUTE (false), authenticated được cấp quyền (true)';
        ELSE
            v_passed := false;
            v_detail := 'Phân quyền Catalog không đúng: anon_exec=' || v_anon_has_priv::text || ', auth_exec=' || v_auth_has_priv::text;
        END IF;

        v_report := v_report || jsonb_build_object(
            'scenario_id', 11,
            'scenario_name', 'Bảo mật Catalog: Thu hồi EXECUTE của anon, cấp cho authenticated',
            'status', CASE WHEN v_passed THEN 'ĐẠT' ELSE 'THẤT BẠI' END,
            'details', v_detail
        );


        -- ----------------------------------------------------------------------
        -- KÍCH HOẠT HOÀN TÁC TOÀN BỘ FIXTURE (ENGINE-LEVEL SUBTRANSACTION ROLLBACK)
        -- ----------------------------------------------------------------------
        RAISE EXCEPTION 'TEST_SUITE_FORCE_ROLLBACK';

    EXCEPTION WHEN OTHERS THEN
        v_rollback_err := SQLERRM;
        -- Khi vào khối EXCEPTION này, engine PostgreSQL đã tự động hoàn tác (ROLLBACK)
        -- toàn bộ thay đổi dữ liệu đã ghi trong tiểu khối BEGIN ở trên.
        IF v_rollback_err = 'TEST_SUITE_FORCE_ROLLBACK' THEN
            RAISE NOTICE '>>> CƠ CHẾ ROLLBACK THÀNH CÔNG: Toàn bộ dữ liệu thử nghiệm đã được engine PostgreSQL hoàn tác sạch sẽ';
        ELSE
            RAISE NOTICE '>>> CƠ CHẾ ROLLBACK KÍCH HOẠT DO NGOẠI LỆ: %', v_rollback_err;
            -- Ghi nhận lỗi gián đoạn setup/tiến trình vào báo cáo với số kịch bản chưa kịp chạy
            v_report := jsonb_build_array(
                jsonb_build_object(
                    'scenario_id', 0,
                    'scenario_name', 'THIẾT LẬP FIXTURE / TIẾN TRÌNH KIỂM THỬ',
                    'status', 'THẤT BẠI',
                    'details', 'Tiến trình bị ngắt do ngoại lệ: ' || v_rollback_err || '. Số kịch bản chưa chạy: ' || (11 - COALESCE(jsonb_array_length(v_report), 0))::text || '/11'
                )
            ) || v_report;
        END IF;
    END;

    -- --------------------------------------------------------------------------
    -- BƯỚC 2: NẠP KẾT QUẢ TỪ BỘ NHỚ VÀO BẢNG TẠM BÁO CÁO (PG_TEMP)
    -- Vì bảng tạm này được nạp sau khi hoàn tác dữ liệu fixture, dữ liệu báo cáo
    -- được bảo toàn nguyên vẹn để hiển thị trong tab Results.
    -- --------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', '', true);
    PERFORM set_config('request.jwt.claim.role', '', true);

    FOR v_item IN SELECT * FROM jsonb_array_elements(v_report) LOOP
        INSERT INTO pg_temp.order_test_report (scenario_id, scenario_name, status, details)
        VALUES (
            (v_item->>'scenario_id')::int,
            v_item->>'scenario_name',
            v_item->>'status',
            v_item->>'details'
        );
        RAISE NOTICE '>>> KỊCH BẢN % [%]: % — %',
            v_item->>'scenario_id',
            v_item->>'status',
            v_item->>'scenario_name',
            v_item->>'details';
    END LOOP;

    -- Kiểm tra phòng ngừa: Đảm bảo không còn bàn ăn hoặc sản phẩm thử nghiệm nào sót lại
    IF EXISTS (
        SELECT 1 FROM public.dining_tables
        WHERE id IN (
            v_table_avail_1_id, v_table_avail_tamper_id, v_table_with_order_id,
            v_table_occupied_id, v_table_reserved_id, v_table_general_id
        )
    ) THEN
        RAISE WARNING 'CẢNH BÁO: Bàn ăn thử nghiệm vẫn còn tồn tại trong cơ sở dữ liệu!';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.products
        WHERE id IN (v_prod_avail_1_id, v_prod_avail_2_id, v_prod_unavail_id)
    ) THEN
        RAISE WARNING 'CẢNH BÁO: Sản phẩm thử nghiệm vẫn còn tồn tại trong cơ sở dữ liệu!';
    END IF;
END;
$$;


-- ==============================================================================
-- BƯỚC C: HIỂN THỊ KẾT QUẢ TRONG TAB RESULTS CỦA SUPABASE SQL EDITOR
-- ==============================================================================

-- 1. BẢNG TỔNG KẾT TỔNG THỂ THEO ĐÚNG YÊU CẦU BẮT BUỘC
-- Đảm bảo chỉ hiển thị 'PASSED' khi có ĐỦ 11 bản ghi và TẤT CẢ 11 bản ghi đều ĐẠT.
-- Nếu thiếu bất kỳ kịch bản nào, setup lỗi hoặc có kịch bản thất bại, trạng thái hiển thị FAILED.
SELECT
    COUNT(*) FILTER (WHERE status = 'ĐẠT' AND scenario_id > 0) AS "Số kịch bản đạt",
    11 AS "Tổng số kịch bản bắt buộc",
    CASE
        WHEN COUNT(*) FILTER (WHERE scenario_id > 0) = 11
             AND COUNT(*) FILTER (WHERE status = 'ĐẠT' AND scenario_id > 0) = 11
             AND NOT EXISTS (SELECT 1 FROM pg_temp.order_test_report WHERE scenario_id = 0)
        THEN 'PASSED'
        ELSE 'FAILED'
    END AS "Trạng thái tổng thể",
    CASE
        WHEN EXISTS (SELECT 1 FROM pg_temp.order_test_report WHERE scenario_id = 0) THEN
            (SELECT details FROM pg_temp.order_test_report WHERE scenario_id = 0)
        WHEN COUNT(*) FILTER (WHERE scenario_id > 0) < 11 THEN
            'Tiến trình chưa hoàn tất: chỉ có ' || COUNT(*)::text || '/11 kịch bản được thực thi'
        WHEN COUNT(*) FILTER (WHERE status = 'THẤT BẠI') > 0 THEN
            'Có ' || COUNT(*) FILTER (WHERE status = 'THẤT BẠI')::text || ' kịch bản kiểm thử không đạt'
        ELSE 'Tất cả 11 kịch bản kiểm thử đều đạt yêu cầu'
    END AS "Chẩn đoán tiến trình"
FROM pg_temp.order_test_report;

-- 2. BẢNG CHI TIẾT TỪNG KỊCH BẢN ĐỂ KIỂM TRA ĐỐI CHIẾU
SELECT
    scenario_id AS "STT",
    scenario_name AS "Kịch bản kiểm thử",
    status AS "Kết quả",
    details AS "Chi tiết thực thi"
FROM pg_temp.order_test_report
ORDER BY scenario_id;


-- ==============================================================================
-- PHẦN PHỤ TRỢ: KIỂM TRA ĐỘC LẬP NGOÀI TRANSACTION CHO ROLE ANON (TÙY CHỌN)
-- Hướng dẫn:
-- - Khối này dùng để kiểm chứng ngoại lệ runtime permission denied (SQLSTATE 42501).
-- - CHẠY RIÊNG RẼ khối này trong một tab khác, KHÔNG chạy chung với script ở trên.
-- ==============================================================================
/*
SET ROLE anon;
-- Lệnh dưới đây PHẢI văng lỗi: "permission denied for function create_full_order"
SELECT public.create_full_order(
    '00000000-0000-0000-0000-000000000000'::uuid,
    '[{"product_id": "00000000-0000-0000-0000-000000000000", "quantity": 1}]'::jsonb
);
RESET ROLE;
*/
