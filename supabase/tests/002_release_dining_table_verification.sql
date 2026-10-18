-- ==============================================================================
-- SMART ORDER — DEDICATED TEST SUITE FOR RPC public.release_dining_table()
-- Test File: supabase/tests/002_release_dining_table_verification.sql
-- Database: PostgreSQL 15+ (Supabase)
-- Phase: C2.4 Hardened Test — RPC Verification & Reserved Table Protection
-- ==============================================================================
-- CẢNH BÁO BẢO MẬT & KIỂM THỬ:
-- - File này là kịch bản kiểm thử tĩnh được chuẩn bị sẵn, CHƯA được thực thi trên PostgreSQL.
-- - Không tuyên bố các kịch bản đã "ĐẠT" trên môi trường thực tế cho đến khi người vận hành
--   trực tiếp chạy toàn bộ script này trên Supabase SQL Editor và kiểm chứng kết quả trong tab Results.
--
-- HƯỚNG DẪN THỰC THI TRÊN SUPABASE DASHBOARD:
-- 1. Mở Supabase Dashboard -> SQL Editor -> Tạo một tab truy vấn mới.
-- 2. Chọn TOÀN BỘ nội dung file (Ctrl+A) và nhấn "Run" trong MỘT LẦN CHẠY DUY NHẤT.
-- 3. Quan sát tab Results:
--    - Bảng 1: Bảng tổng kết ("Số kịch bản đạt", "Tổng số kịch bản", "Trạng thái tổng thể").
--    - Bảng 2: Danh sách chi tiết từng kịch bản và lý do đạt/thất bại.
-- 4. Quan sát tab Messages: Theo dõi nhật ký hoàn tác subtransaction và thông báo từng bước.
--
-- GIẢI THÍCH VỀ CƠ CHẾ TRANSACTION ROLLBACK & PHẠM VI PG_TEMP:
-- 1. TẠI SAO PHẢI CHẠY TOÀN BỘ FILE TRONG MỘT LẦN CHẠY?
--    - Bảng báo cáo được lưu trong `pg_temp` (schema phiên tạm thời của PostgreSQL).
--    - `pg_temp` chỉ tồn tại trong phiên kết nối backend của lệnh thực thi. Nếu người vận hành
--      bôi đen chạy từng phần ở các lần bấm Run khác nhau qua Connection Pooler (PgBouncer),
--      kết nối có thể bị đổi khiến bảng tạm không tìm thấy. Do đó, PHẢI chạy toàn bộ file một lần.
--
-- 2. CƠ CHẾ HOÀN TÁC DỮ LIỆU BẰNG SUBTRANSACTION (ENGINE-LEVEL ROLLBACK):
--    - Toàn bộ việc chèn dữ liệu kiểm thử (auth.users, dining_tables, orders) và gọi RPC được
--      thực hiện bên trong một tiểu khối PL/pgSQL (subtransaction).
--    - Kết thúc kiểm thử, tiểu khối chủ động phát sinh ngoại lệ nội bộ để engine PostgreSQL
--      tự động ROLLBACK toàn bộ dữ liệu trên bảng vật lý về trạng thái nguyên vẹn ban đầu.
--    - Bộ nhớ biến PL/pgSQL (v_report) không bị rollback theo quy chuẩn của PostgreSQL,
--      cho phép giữ lại toàn bộ kết quả để nạp vào bảng tạm sau khi rollback hoàn tất.
--    - LƯU Ý MINH BẠCH: Cơ chế này hoàn tác dữ liệu ở cấp độ engine PostgreSQL trong phiên hiện tại,
--      nhưng không bảo đảm 100% nếu phiên bị ngắt kết nối vật lý (mất mạng/crash server) trước khi
--      khối lệnh kết thúc. Không có cơ chế nào có thể tuyên bố bảo đảm tuyệt đối trong mọi thảm họa.
--
-- 3. GIỚI HẠN CỦA VIỆC MÔ PHỎNG JWT BẰNG SET_CONFIG:
--    - `set_config('request.jwt.claim.sub', ...)` chỉ cung cấp ngữ cảnh giả lập cho hàm `auth.uid()`
--      bên trong các hàm SECURITY DEFINER của PostgreSQL.
--    - Việc này KHÔNG kiểm tra được:
--      + Chữ ký mật mã JWT (HMAC-SHA256/RSA) và thời hạn hết hạn token (exp).
--      + Tầng Kong API Gateway (Rate limiting, CORS, xác thực API Key).
--      + Tầng PostgREST Web Server (Reload schema cache, chuyển đổi role qua HTTP Header).
--    - Bắt buộc phải có bài kiểm thử tích hợp (Integration Test) qua Supabase API với token thật
--      để kiểm chứng toàn diện luồng người dùng trên môi trường thực.
-- ==============================================================================

-- BƯỚC A: KHỞI TẠO BẢNG TẠM BÁO CÁO (CHỈ TỒN TẠI TRONG PHIÊN THỰC THI HIỆN TẠI)
CREATE TEMP TABLE IF NOT EXISTS pg_temp.release_test_report (
    scenario_id int PRIMARY KEY,
    scenario_name text NOT NULL,
    status text NOT NULL,
    details text NOT NULL
);
TRUNCATE pg_temp.release_test_report;


-- BƯỚC B: THỰC THI KIỂM THỬ TRONG SUBTRANSACTION VÀ TỰ ĐỘNG ROLLBACK FIXTURE
DO $$
DECLARE
    -- Định danh tài khoản kiểm thử ngẫu nhiên
    v_staff_id uuid := gen_random_uuid();
    v_admin_id uuid := gen_random_uuid();
    v_kitchen_id uuid := gen_random_uuid();
    v_staff_email text := 'staff_test_' || substr(gen_random_uuid()::text, 1, 8) || '@smartorder.test';
    v_admin_email text := 'admin_test_' || substr(gen_random_uuid()::text, 1, 8) || '@smartorder.test';
    v_kitchen_email text := 'kitchen_test_' || substr(gen_random_uuid()::text, 1, 8) || '@smartorder.test';

    -- Định danh bàn ăn kiểm thử ngẫu nhiên
    v_table_reserved_id uuid := gen_random_uuid();
    v_table_available_id uuid := gen_random_uuid();
    v_table_occupied_id uuid := gen_random_uuid();
    v_table_with_order_id uuid := gen_random_uuid();

    -- Định danh đơn hàng kiểm thử ngẫu nhiên
    v_active_order_id uuid := gen_random_uuid();
    v_test_order_code text := 'TEST-ORD-' || substr(gen_random_uuid()::text, 1, 8);

    -- Biến theo dõi kết quả trong bộ nhớ phiên PL/pgSQL
    v_report jsonb := '[]'::jsonb;
    v_passed boolean;
    v_detail text;
    v_table_status_check text;
    v_res_available jsonb;
    v_res_occupied jsonb;
    v_item jsonb;
    v_rollback_err text;
BEGIN
    RAISE NOTICE '====================================================================';
    RAISE NOTICE 'BẮT ĐẦU KIỂM THỬ TOÀN DIỆN RPC public.release_dining_table()';
    RAISE NOTICE '====================================================================';

    -- --------------------------------------------------------------------------
    -- BƯỚC 1: TIỂU KHỐI TRANSACTION TỰ HOÀN TÁC (AUTO-ROLLBACK SUBTRANSACTION)
    -- Dữ liệu fixture chỉ tồn tại tạm thời bên trong tiểu khối này.
    -- Khi kết thúc kiểm thử, tiểu khối chủ động văng ngoại lệ TEST_SUITE_FORCE_ROLLBACK
    -- để engine PostgreSQL hoàn tác 100% dữ liệu đã ghi vào auth.users, dining_tables, orders.
    -- --------------------------------------------------------------------------
    BEGIN
        -- Làm sạch cấu hình phiên GUC
        PERFORM set_config('request.jwt.claim.sub', '', true);
        PERFORM set_config('request.jwt.claim.role', '', true);

        -- 1.1. Tạo 3 tài khoản trong auth.users (Trigger on_auth_user_created tự tạo profiles role = 'staff')
        INSERT INTO auth.users (id, email, raw_user_meta_data, role, aud)
        VALUES
            (v_staff_id, v_staff_email, '{"full_name":"Test Staff Runner"}'::jsonb, 'authenticated', 'authenticated'),
            (v_admin_id, v_admin_email, '{"full_name":"Test Admin Runner"}'::jsonb, 'authenticated', 'authenticated'),
            (v_kitchen_id, v_kitchen_email, '{"full_name":"Test Kitchen Runner"}'::jsonb, 'authenticated', 'authenticated');

        -- 1.2. Nâng quyền Admin và Kitchen từ phiên DBA (session_user = postgres, JWT role IS NULL)
        UPDATE public.profiles SET role = 'admin' WHERE id = v_admin_id;
        UPDATE public.profiles SET role = 'kitchen' WHERE id = v_kitchen_id;

        -- 1.3. Tạo 4 bàn ăn kiểm thử đại diện cho các trạng thái nghiệp vụ
        INSERT INTO public.dining_tables (id, name, capacity, area, status)
        VALUES
            (v_table_reserved_id, 'TEST_TBL_RESERVED_' || substr(gen_random_uuid()::text, 1, 6), 4, 'Khu Test', 'reserved'),
            (v_table_available_id, 'TEST_TBL_AVAILABLE_' || substr(gen_random_uuid()::text, 1, 6), 4, 'Khu Test', 'available'),
            (v_table_occupied_id, 'TEST_TBL_OCCUPIED_' || substr(gen_random_uuid()::text, 1, 6), 4, 'Khu Test', 'occupied'),
            (v_table_with_order_id, 'TEST_TBL_WITH_ORDER_' || substr(gen_random_uuid()::text, 1, 6), 4, 'Khu Test', 'occupied');

        -- 1.4. Tạo 1 đơn hàng kiểm thử đang xử lý (pending) gắn với bàn v_table_with_order_id
        INSERT INTO public.orders (id, order_code, table_id, staff_id, status, total_amount, payment_status)
        VALUES (
            v_active_order_id,
            v_test_order_code,
            v_table_with_order_id,
            v_staff_id,
            'pending',
            0.00,
            'unpaid'
        );

        -- ----------------------------------------------------------------------
        -- KỊCH BẢN 1: STAFF GỌI BÀN RESERVED PHẢI BỊ TỪ CHỐI
        -- ----------------------------------------------------------------------
        v_passed := false;
        v_detail := '';
        PERFORM set_config('request.jwt.claim.sub', v_staff_id::text, true);
        PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

        BEGIN
            PERFORM public.release_dining_table(v_table_reserved_id);
            v_passed := false;
            v_detail := 'Lỗ hổng: RPC không chặn nhân viên Staff giải phóng bàn reserved';
        EXCEPTION WHEN OTHERS THEN
            IF SQLERRM LIKE '%Bàn đang ở trạng thái đặt trước (reserved)%' THEN
                v_passed := true;
                v_detail := 'Chặn chính xác với thông báo nghiệp vụ mong đợi';
            ELSE
                v_passed := false;
                v_detail := 'Bắt lỗi sai thông báo: ' || SQLERRM;
            END IF;
        END;

        v_report := v_report || jsonb_build_object(
            'scenario_id', 1,
            'scenario_name', 'Staff gọi giải phóng bàn reserved',
            'status', CASE WHEN v_passed THEN 'ĐẠT' ELSE 'THẤT BẠI' END,
            'details', v_detail
        );

        -- ----------------------------------------------------------------------
        -- KỊCH BẢN 2: ADMIN GỌI BÀN RESERVED CŨNG PHẢI BỊ TỪ CHỐI
        -- ----------------------------------------------------------------------
        v_passed := false;
        v_detail := '';
        PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
        PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

        BEGIN
            PERFORM public.release_dining_table(v_table_reserved_id);
            v_passed := false;
            v_detail := 'Lỗ hổng: RPC không chặn Quản trị viên Admin giải phóng bàn reserved';
        EXCEPTION WHEN OTHERS THEN
            IF SQLERRM LIKE '%Bàn đang ở trạng thái đặt trước (reserved)%' THEN
                v_passed := true;
                v_detail := 'Chặn chính xác cả Quản trị viên theo quy định nghiệp vụ';
            ELSE
                v_passed := false;
                v_detail := 'Bắt lỗi sai thông báo: ' || SQLERRM;
            END IF;
        END;

        v_report := v_report || jsonb_build_object(
            'scenario_id', 2,
            'scenario_name', 'Admin gọi giải phóng bàn reserved',
            'status', CASE WHEN v_passed THEN 'ĐẠT' ELSE 'THẤT BẠI' END,
            'details', v_detail
        );

        -- ----------------------------------------------------------------------
        -- KỊCH BẢN 3: XÁC MINH TRẠNG THÁI BÀN VẪN BẢO TOÀN LÀ RESERVED
        -- ----------------------------------------------------------------------
        v_passed := false;
        v_detail := '';
        SELECT status INTO v_table_status_check
        FROM public.dining_tables
        WHERE id = v_table_reserved_id;

        IF v_table_status_check = 'reserved' THEN
            v_passed := true;
            v_detail := 'Trạng thái status = reserved được giữ nguyên vẹn trong DB';
        ELSE
            v_passed := false;
            v_detail := 'Trạng thái bàn bị thay đổi thành: ' || COALESCE(v_table_status_check, 'NULL');
        END IF;

        v_report := v_report || jsonb_build_object(
            'scenario_id', 3,
            'scenario_name', 'Bảo toàn trạng thái bàn reserved',
            'status', CASE WHEN v_passed THEN 'ĐẠT' ELSE 'THẤT BẠI' END,
            'details', v_detail
        );

        -- ----------------------------------------------------------------------
        -- KỊCH BẢN 4: XỬ LÝ IDEMPOTENT TRÊN BÀN AVAILABLE
        -- ----------------------------------------------------------------------
        v_passed := false;
        v_detail := '';
        PERFORM set_config('request.jwt.claim.sub', v_staff_id::text, true);
        PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

        BEGIN
            v_res_available := public.release_dining_table(v_table_available_id);
            IF (v_res_available->>'success')::boolean IS TRUE
               AND (v_res_available->>'status') = 'available'
               AND (v_res_available->>'message') = 'Bàn ăn hiện đã ở trạng thái trống' THEN
                v_passed := true;
                v_detail := 'Trả về success: true và status: available tức thì';
            ELSE
                v_passed := false;
                v_detail := 'Phản hồi không khớp kỳ vọng: ' || COALESCE(v_res_available::text, 'NULL');
            END IF;
        EXCEPTION WHEN OTHERS THEN
            v_passed := false;
            v_detail := 'Ngoại lệ phát sinh khi gọi bàn available: ' || SQLERRM;
        END;

        v_report := v_report || jsonb_build_object(
            'scenario_id', 4,
            'scenario_name', 'Xử lý Idempotent trên bàn available',
            'status', CASE WHEN v_passed THEN 'ĐẠT' ELSE 'THẤT BẠI' END,
            'details', v_detail
        );

        -- ----------------------------------------------------------------------
        -- KỊCH BẢN 5: GIẢI PHÓNG BÀN OCCUPIED KHÔNG CÓ ĐƠN HÀNG THÀNH CÔNG
        -- ----------------------------------------------------------------------
        v_passed := false;
        v_detail := '';
        BEGIN
            v_res_occupied := public.release_dining_table(v_table_occupied_id);
            IF (v_res_occupied->>'success')::boolean IS TRUE
               AND (v_res_occupied->>'status') = 'available'
               AND (v_res_occupied->>'message') = 'Đã dọn dẹp và giải phóng bàn thành công' THEN

                SELECT status INTO v_table_status_check FROM public.dining_tables WHERE id = v_table_occupied_id;
                IF v_table_status_check = 'available' THEN
                    v_passed := true;
                    v_detail := 'Cập nhật trạng thái bàn sang available thành công';
                ELSE
                    v_passed := false;
                    v_detail := 'DB chưa cập nhật: status = ' || COALESCE(v_table_status_check, 'NULL');
                END IF;
            ELSE
                v_passed := false;
                v_detail := 'Phản hồi không khớp kỳ vọng: ' || COALESCE(v_res_occupied::text, 'NULL');
            END IF;
        EXCEPTION WHEN OTHERS THEN
            v_passed := false;
            v_detail := 'Ngoại lệ phát sinh: ' || SQLERRM;
        END;

        v_report := v_report || jsonb_build_object(
            'scenario_id', 5,
            'scenario_name', 'Giải phóng bàn occupied không có đơn',
            'status', CASE WHEN v_passed THEN 'ĐẠT' ELSE 'THẤT BẠI' END,
            'details', v_detail
        );

        -- ----------------------------------------------------------------------
        -- KỊCH BẢN 6: CHẶN GIẢI PHÓNG BÀN CÒN ĐƠN HÀNG DỞ DANG
        -- ----------------------------------------------------------------------
        v_passed := false;
        v_detail := '';
        BEGIN
            PERFORM public.release_dining_table(v_table_with_order_id);
            v_passed := false;
            v_detail := 'Lỗ hổng: Bàn có đơn hàng dở dang vẫn bị giải phóng';
        EXCEPTION WHEN OTHERS THEN
            IF SQLERRM LIKE '%đơn hàng chưa hoàn tất tại bàn này%' THEN
                v_passed := true;
                v_detail := 'Chặn chính xác khi bàn còn đơn hàng ở trạng thái pending';
            ELSE
                v_passed := false;
                v_detail := 'Bắt lỗi sai thông báo: ' || SQLERRM;
            END IF;
        END;

        v_report := v_report || jsonb_build_object(
            'scenario_id', 6,
            'scenario_name', 'Chặn bàn còn đơn hàng dở dang',
            'status', CASE WHEN v_passed THEN 'ĐẠT' ELSE 'THẤT BẠI' END,
            'details', v_detail
        );

        -- ----------------------------------------------------------------------
        -- KỊCH BẢN 7: VAI TRÒ KHÔNG HỢP LỆ (KITCHEN) BỊ TỪ CHỐI PHÂN QUYỀN
        -- ----------------------------------------------------------------------
        v_passed := false;
        v_detail := '';
        PERFORM set_config('request.jwt.claim.sub', v_kitchen_id::text, true);
        PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

        BEGIN
            PERFORM public.release_dining_table(v_table_available_id);
            v_passed := false;
            v_detail := 'Lỗ hổng: Vai trò Kitchen vẫn có thể gọi giải phóng bàn';
        EXCEPTION WHEN OTHERS THEN
            IF SQLERRM LIKE '%Chỉ Quản trị viên hoặc Nhân viên phục vụ mới có quyền giải phóng bàn%' THEN
                v_passed := true;
                v_detail := 'Chặn chính xác tại bước kiểm tra vai trò người gọi (Check 2 - RBAC)';
            ELSE
                v_passed := false;
                v_detail := 'Bắt lỗi sai thông báo: ' || SQLERRM;
            END IF;
        END;

        v_report := v_report || jsonb_build_object(
            'scenario_id', 7,
            'scenario_name', 'Chặn vai trò không hợp lệ (Kitchen)',
            'status', CASE WHEN v_passed THEN 'ĐẠT' ELSE 'THẤT BẠI' END,
            'details', v_detail
        );

        -- ----------------------------------------------------------------------
        -- KỊCH BẢN 8: NGƯỜI DÙNG CHƯA ĐĂNG NHẬP (AUTH.UID IS NULL) BỊ TỪ CHỐI
        -- ----------------------------------------------------------------------
        v_passed := false;
        v_detail := '';
        PERFORM set_config('request.jwt.claim.sub', '', true);
        PERFORM set_config('request.jwt.claim.role', '', true);

        BEGIN
            PERFORM public.release_dining_table(v_table_available_id);
            v_passed := false;
            v_detail := 'Lỗ hổng: Người dùng chưa đăng nhập vẫn gọi được RPC';
        EXCEPTION WHEN OTHERS THEN
            IF SQLERRM LIKE '%Yêu cầu xác thực: Người dùng chưa đăng nhập hệ thống%' THEN
                v_passed := true;
                v_detail := 'Chặn chính xác khi auth.uid() IS NULL (Check 1 - Authentication)';
            ELSE
                v_passed := false;
                v_detail := 'Bắt lỗi sai thông báo: ' || SQLERRM;
            END IF;
        END;

        v_report := v_report || jsonb_build_object(
            'scenario_id', 8,
            'scenario_name', 'Chặn người dùng chưa đăng nhập',
            'status', CASE WHEN v_passed THEN 'ĐẠT' ELSE 'THẤT BẠI' END,
            'details', v_detail
        );

        -- ----------------------------------------------------------------------
        -- KỊCH BẢN 9: KIỂM TRA QUYỀN CATALOG CỦA ROLE ANON
        -- ----------------------------------------------------------------------
        v_passed := false;
        v_detail := '';
        IF has_function_privilege('anon', 'public.release_dining_table(uuid)', 'EXECUTE') THEN
            v_passed := false;
            v_detail := 'Lỗ hổng: Role anon vẫn có quyền EXECUTE trong catalog';
        ELSE
            v_passed := true;
            v_detail := 'System catalog xác nhận quyền EXECUTE đã bị thu hồi hoàn toàn khỏi role anon';
        END IF;

        v_report := v_report || jsonb_build_object(
            'scenario_id', 9,
            'scenario_name', 'Thu hồi quyền EXECUTE role anon',
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
                    'details', 'Tiến trình bị ngắt do ngoại lệ: ' || v_rollback_err || '. Số kịch bản chưa chạy: ' || (9 - COALESCE(jsonb_array_length(v_report), 0))::text || '/9'
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
        INSERT INTO pg_temp.release_test_report (scenario_id, scenario_name, status, details)
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

    -- Kiểm tra phòng ngừa: Đảm bảo bảng dining_tables không còn bàn thử nghiệm
    IF EXISTS (SELECT 1 FROM public.dining_tables WHERE id IN (v_table_reserved_id, v_table_available_id, v_table_occupied_id, v_table_with_order_id)) THEN
        RAISE WARNING 'CẢNH BÁO: Bàn ăn thử nghiệm vẫn còn tồn tại trong cơ sở dữ liệu!';
    END IF;
END;
$$;


-- ==============================================================================
-- BƯỚC C: HIỂN THỊ KẾT QUẢ TRONG TAB RESULTS CỦA SUPABASE SQL EDITOR
-- ==============================================================================

-- 1. BẢNG TỔNG KẾT TỔNG THỂ THEO ĐÚNG YÊU CẦU BẮT BUỘC
-- Đảm bảo chỉ hiển thị 'PASSED' khi có ĐỦ 9 bản ghi và TẤT CẢ 9 bản ghi đều ĐẠT.
-- Nếu thiếu bất kỳ kịch bản nào, setup lỗi hoặc có kịch bản thất bại, trạng thái hiển thị FAILED.
SELECT
    COUNT(*) FILTER (WHERE status = 'ĐẠT' AND scenario_id > 0) AS "Số kịch bản đạt",
    9 AS "Tổng số kịch bản bắt buộc",
    CASE
        WHEN COUNT(*) FILTER (WHERE scenario_id > 0) = 9
             AND COUNT(*) FILTER (WHERE status = 'ĐẠT' AND scenario_id > 0) = 9
             AND NOT EXISTS (SELECT 1 FROM pg_temp.release_test_report WHERE scenario_id = 0)
        THEN 'PASSED'
        ELSE 'FAILED'
    END AS "Trạng thái tổng thể",
    CASE
        WHEN EXISTS (SELECT 1 FROM pg_temp.release_test_report WHERE scenario_id = 0) THEN
            (SELECT details FROM pg_temp.release_test_report WHERE scenario_id = 0)
        WHEN COUNT(*) FILTER (WHERE scenario_id > 0) < 9 THEN
            'Tiến trình chưa hoàn tất: chỉ có ' || COUNT(*)::text || '/9 kịch bản được thực thi'
        WHEN COUNT(*) FILTER (WHERE status = 'THẤT BẠI') > 0 THEN
            'Có ' || COUNT(*) FILTER (WHERE status = 'THẤT BẠI')::text || ' kịch bản kiểm thử không đạt'
        ELSE 'Tất cả 9 kịch bản kiểm thử đều đạt yêu cầu'
    END AS "Chẩn đoán tiến trình"
FROM pg_temp.release_test_report;

-- 2. BẢNG CHI TIẾT TỪNG KỊCH BẢN ĐỂ KIỂM TRA ĐỐI CHIẾU
SELECT
    scenario_id AS "STT",
    scenario_name AS "Kịch bản kiểm thử",
    status AS "Kết quả",
    details AS "Chi tiết thực thi"
FROM pg_temp.release_test_report
ORDER BY scenario_id;


-- ==============================================================================
-- PHẦN PHỤ TRỢ: KIỂM TRA ĐỘC LẬP NGOÀI TRANSACTION CHO ROLE ANON (TÙY CHỌN)
-- Hướng dẫn:
-- - Khối này dùng để kiểm chứng ngoại lệ runtime permission denied (SQLSTATE 42501).
-- - CHẠY RIÊNG RẼ khối này trong một tab khác, KHÔNG chạy chung với script ở trên.
-- ==============================================================================
/*
SET ROLE anon;
-- Lệnh dưới đây PHẢI văng lỗi: "permission denied for function release_dining_table"
SELECT public.release_dining_table('00000000-0000-0000-0000-000000000000'::uuid);
RESET ROLE;
*/
