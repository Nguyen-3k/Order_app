-- ==============================================================================
-- SMART ORDER — DATABASE INITIAL MIGRATION SCRIPT (AUDITED & HARDENED C2.3)
-- Migration File: supabase/migrations/001_initial_schema.sql
-- Database: PostgreSQL 15+ (Supabase)
-- Phase: C2.3 — Critical Security & Concurrency Refactoring
-- ==============================================================================
-- GHI CHÚ BẢO MẬT & BẢO TRÌ HỆ THỐNG:
-- 1. File migration này được chuẩn bị để rà soát thủ công, CHƯA ĐƯỢC THỰC THI TRÊN SUPABASE THẬT.
-- 2. Hỗ trợ chạy lại an toàn (Idempotent / Re-run Safe):
--    - Dùng CREATE TABLE IF NOT EXISTS, CREATE INDEX IF NOT EXISTS.
--    - Dùng DROP TRIGGER IF EXISTS trước mỗi CREATE TRIGGER.
--    - Dùng DROP POLICY IF EXISTS trước mỗi CREATE POLICY.
--    - Dùng CREATE OR REPLACE FUNCTION cho tất cả hàm.
--    - Dùng ON CONFLICT (name) DO UPDATE / WHERE NOT EXISTS cho Seed Data.
--    - Tuyệt đối KHÔNG dùng DROP TABLE và KHÔNG xóa dữ liệu để sửa lỗi chạy lại.
-- 3. Múi giờ chuẩn: Cột thời gian lưu TIMESTAMPTZ (UTC), sinh mã đơn neo theo ngày Việt Nam (UTC+7 / Asia/Ho_Chi_Minh).
-- 4. Nguyên tắc Zero-Direct-Write (Tất cả thao tác ghi trên orders, order_items, payments, dining_tables phải qua RPC):
--    - Thu hồi toàn bộ quyền của role 'anon'.
--    - Thu hồi quyền INSERT, UPDATE, DELETE trực tiếp trên orders, order_items, payments, dining_tables từ 'authenticated'.
--    - Toàn bộ thay đổi dữ liệu nghiệp vụ bắt buộc đi qua các hàm RPC có kiểm soát và khóa hàng phân cấp.
--    - Tất cả hàm SECURITY DEFINER được neo cứng search_path = public, pg_temp.
-- 5. Giới hạn nghiệp vụ phiên bản C2 (chưa triển khai ở giai đoạn này, sẽ bổ sung ở Phase sau):
--    - Chưa tích hợp Webhook cổng thanh toán trực tuyến (VNPay/MoMo/ZaloPay).
--    - Chưa hỗ trợ tách hóa đơn (Split bill) hoặc gộp bàn (Merge tables).
--    - Trạng thái 'refunded' đã có trong CHECK constraint nhưng quy trình hoàn tiền tự động qua cổng cần thực hiện sau.
-- 6. Quản trị Danh mục (Categories) & Sản phẩm (Products) của Admin:
--    - Nhằm bảo đảm nguyên tắc Zero-Direct-Write, quyền ghi trực tiếp trên categories và products đã bị thu hồi từ authenticated.
--    - Các RPC nghiệp vụ quản trị riêng cho Admin (admin_upsert_category, admin_upsert_product, admin_toggle_product)
--      chưa được lập trình ở C2 và sẽ được triển khai độc lập ở giai đoạn tiếp theo (Phase C3). Hiện tại thực đơn được khởi tạo qua Seed Data.
-- ==============================================================================

-- Bắt đầu Transaction
BEGIN;

-- ------------------------------------------------------------------------------
-- 0. TIỆN ÍCH HỆ THỐNG & EXTENSIONS
-- ------------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ------------------------------------------------------------------------------
-- 1. BẢNG 1: PROFILES (HỒ SƠ NHÂN SỰ & VAI TRÒ HỆ THỐNG)
-- ------------------------------------------------------------------------------
-- Khóa chính id liên kết 1-1 với auth.users(id) của Supabase.
-- Tuyệt đối không lưu mật khẩu. Mật khẩu do Supabase Auth quản lý độc lập.
CREATE TABLE IF NOT EXISTS public.profiles (
    id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name text NOT NULL CHECK (length(trim(full_name)) > 0),
    role text NOT NULL CHECK (role IN ('admin', 'staff', 'kitchen', 'bar')),
    phone text,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.profiles IS 'Thông tin hồ sơ và phân quyền vai trò nhân viên Smart Order';
COMMENT ON COLUMN public.profiles.id IS 'Khóa chính, khớp với auth.users(id)';
COMMENT ON COLUMN public.profiles.role IS 'Vai trò: admin (Quản trị), staff (Phục vụ), kitchen (Bếp), bar (Pha chế)';

-- ------------------------------------------------------------------------------
-- 2. BẢNG 2: CATEGORIES (DANH MỤC THỰC ĐƠN)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.categories (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL UNIQUE CHECK (length(trim(name)) > 0),
    description text,
    display_order int NOT NULL DEFAULT 0,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.categories IS 'Danh mục phân loại thực đơn món ăn và đồ uống';

-- ------------------------------------------------------------------------------
-- 3. BẢNG 3: PRODUCTS (SẢN PHẨM: MÓN ĂN & THỨC UỐNG)
-- ------------------------------------------------------------------------------
-- station ('kitchen' / 'bar') phân định trạm chế biến chịu trách nhiệm.
CREATE TABLE IF NOT EXISTS public.products (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    category_id uuid REFERENCES public.categories(id) ON DELETE SET NULL,
    name text NOT NULL CHECK (length(trim(name)) > 0),
    description text,
    price numeric(12, 2) NOT NULL CHECK (price >= 0),
    station text NOT NULL CHECK (station IN ('kitchen', 'bar')),
    image_url text,
    is_available boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.products IS 'Danh sách sản phẩm kinh doanh của nhà hàng';
COMMENT ON COLUMN public.products.station IS 'Trạm xử lý: kitchen (Bếp nấu món), bar (Quầy pha chế đồ uống)';
COMMENT ON COLUMN public.products.is_available IS 'Cờ quản lý hết món / ngừng kinh doanh thay vì xóa cứng dữ liệu';

-- ------------------------------------------------------------------------------
-- 4. BẢNG 4: DINING_TABLES (SƠ ĐỒ BÀN ĂN)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.dining_tables (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL UNIQUE CHECK (length(trim(name)) > 0),
    capacity int NOT NULL DEFAULT 4 CHECK (capacity > 0),
    area text NOT NULL DEFAULT 'Tầng 1',
    status text NOT NULL DEFAULT 'available' CHECK (status IN ('available', 'occupied', 'reserved')),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.dining_tables IS 'Quản lý danh sách bàn ăn, sức chứa và trạng thái phục vụ';
COMMENT ON COLUMN public.dining_tables.status IS 'Trạng thái bàn: available (Bàn trống), occupied (Đang có khách), reserved (Đặt trước)';

-- ------------------------------------------------------------------------------
-- 5. BẢNG 5: ORDERS (ĐƠN GỌI MÓN TỔNG HỢP)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.orders (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    order_code text NOT NULL UNIQUE CHECK (length(trim(order_code)) > 0),
    table_id uuid NOT NULL REFERENCES public.dining_tables(id) ON DELETE RESTRICT,
    staff_id uuid REFERENCES public.profiles(id) ON DELETE RESTRICT,
    status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'in_progress', 'completed', 'cancelled')),
    payment_status text NOT NULL DEFAULT 'unpaid' CHECK (payment_status IN ('unpaid', 'partially_paid', 'paid', 'refunded')),
    total_amount numeric(12, 2) NOT NULL DEFAULT 0 CHECK (total_amount >= 0),
    notes text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.orders IS 'Đơn hàng tổng thể của một lượt dùng bữa tại bàn';
COMMENT ON COLUMN public.orders.order_code IS 'Mã đơn sinh tự động dạng ORD-YYYYMMDD-001';
COMMENT ON COLUMN public.orders.status IS 'Vòng đời đơn: pending -> in_progress -> completed (hoặc cancelled)';
COMMENT ON COLUMN public.orders.payment_status IS 'Trạng thái thanh toán: unpaid -> partially_paid -> paid (hoặc refunded)';
COMMENT ON COLUMN public.orders.total_amount IS 'Tổng tiền các món không bị hủy, tự động cập nhật qua Database Trigger';

-- ------------------------------------------------------------------------------
-- 6. BẢNG 6: ORDER_ITEMS (CHI TIẾT MÓN TRONG ĐƠN)
-- ------------------------------------------------------------------------------
-- Snapshot tên món và giá bán tại thời điểm đặt, bảo toàn lịch sử hóa đơn.
CREATE TABLE IF NOT EXISTS public.order_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    product_id uuid REFERENCES public.products(id) ON DELETE RESTRICT,
    item_name text NOT NULL CHECK (length(trim(item_name)) > 0),
    unit_price numeric(12, 2) NOT NULL CHECK (unit_price >= 0),
    quantity int NOT NULL CHECK (quantity > 0),
    subtotal numeric(12, 2) NOT NULL CHECK (subtotal = unit_price * quantity),
    notes text,
    station text NOT NULL CHECK (station IN ('kitchen', 'bar')),
    status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'preparing', 'ready', 'served', 'cancelled')),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.order_items IS 'Chi tiết từng món trong đơn gửi tới Bếp và Quầy Bar';
COMMENT ON COLUMN public.order_items.status IS 'Trạng thái món: pending -> preparing -> ready -> served (hoặc cancelled)';
COMMENT ON COLUMN public.order_items.subtotal IS 'Thành tiền dòng món, được kiểm soát bằng CHECK (subtotal = unit_price * quantity)';

-- ------------------------------------------------------------------------------
-- 7. BẢNG 7: PAYMENTS (LỊCH SỬ GIAO DỊCH THANH TOÁN)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.payments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE RESTRICT,
    amount numeric(12, 2) NOT NULL CHECK (amount > 0),
    payment_method text NOT NULL DEFAULT 'cash' CHECK (payment_method IN ('cash', 'banking_qr', 'card')),
    status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'failed', 'refunded')),
    transaction_code text,
    processed_by uuid REFERENCES public.profiles(id) ON DELETE RESTRICT,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.payments IS 'Ghi nhận các giao dịch thanh toán tài chính cho đơn hàng';
COMMENT ON COLUMN public.payments.payment_method IS 'Phương thức: cash (Tiền mặt), banking_qr (Chuyển khoản QR), card (Thẻ POS)';

-- ------------------------------------------------------------------------------
-- 8. BẢNG PHỤ TRỢ: ORDER_COUNTERS (BỘ ĐẾM MÃ ĐƠN HÀNG THEO NGÀY)
-- ------------------------------------------------------------------------------
-- Sử dụng upsert nguyên tử trên bảng này để sinh mã ORD-YYYYMMDD-001 an toàn concurrency.
CREATE TABLE IF NOT EXISTS public.order_counters (
    order_date date PRIMARY KEY,
    last_seq int NOT NULL DEFAULT 0
);

COMMENT ON TABLE public.order_counters IS 'Bộ đếm số thứ tự đơn hàng theo ngày phục vụ sinh mã đơn an toàn';

-- ------------------------------------------------------------------------------
-- 9. TẠO INDEXES PHỤC VỤ HIỆU NĂNG VÀ TRUY VẤN
-- ------------------------------------------------------------------------------
-- Lưu ý: Các khóa chính (PK) và ràng buộc UNIQUE đã được PostgreSQL tự động tạo index.
CREATE INDEX IF NOT EXISTS idx_products_category_id ON public.products(category_id);
CREATE INDEX IF NOT EXISTS idx_products_station ON public.products(station);
CREATE INDEX IF NOT EXISTS idx_products_is_available ON public.products(is_available);

CREATE INDEX IF NOT EXISTS idx_orders_table_id ON public.orders(table_id);
CREATE INDEX IF NOT EXISTS idx_orders_staff_id ON public.orders(staff_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON public.orders(status);
CREATE INDEX IF NOT EXISTS idx_orders_payment_status ON public.orders(payment_status);
CREATE INDEX IF NOT EXISTS idx_orders_created_at ON public.orders(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_order_items_order_id ON public.order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_items_product_id ON public.order_items(product_id);
CREATE INDEX IF NOT EXISTS idx_order_items_station_status ON public.order_items(station, status);

CREATE INDEX IF NOT EXISTS idx_payments_order_id ON public.payments(order_id);
CREATE INDEX IF NOT EXISTS idx_payments_processed_by ON public.payments(processed_by);
CREATE INDEX IF NOT EXISTS idx_payments_status ON public.payments(status);

-- Unique index có điều kiện ngăn chặn tuyệt đối việc trùng lặp transaction_code không rỗng đã hoàn tất (MỤC C)
CREATE UNIQUE INDEX IF NOT EXISTS idx_payments_unique_transaction_code
ON public.payments (trim(transaction_code))
WHERE transaction_code IS NOT NULL AND length(trim(transaction_code)) > 0 AND status = 'completed';

-- ------------------------------------------------------------------------------
-- 10. DATABASE TRIGGERS
-- ------------------------------------------------------------------------------

-- Trigger 1: Tự động cập nhật cột updated_at
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_profiles_updated_at ON public.profiles;
CREATE TRIGGER trg_profiles_updated_at BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

DROP TRIGGER IF EXISTS trg_categories_updated_at ON public.categories;
CREATE TRIGGER trg_categories_updated_at BEFORE UPDATE ON public.categories FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

DROP TRIGGER IF EXISTS trg_products_updated_at ON public.products;
CREATE TRIGGER trg_products_updated_at BEFORE UPDATE ON public.products FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

DROP TRIGGER IF EXISTS trg_dining_tables_updated_at ON public.dining_tables;
CREATE TRIGGER trg_dining_tables_updated_at BEFORE UPDATE ON public.dining_tables FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

DROP TRIGGER IF EXISTS trg_orders_updated_at ON public.orders;
CREATE TRIGGER trg_orders_updated_at BEFORE UPDATE ON public.orders FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

DROP TRIGGER IF EXISTS trg_order_items_updated_at ON public.order_items;
CREATE TRIGGER trg_order_items_updated_at BEFORE UPDATE ON public.order_items FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();


-- Trigger 2: Bảo vệ chống leo thang đặc quyền (Privilege Escalation) trên bảng profiles (MỤC A)
-- LƯU Ý BẢO MẬT: Hàm này cố tình KHÔNG khai báo SECURITY DEFINER để bảo toàn thông tin người gọi thực tế.
-- Không dựa vào current_user để nhận diện người gọi là postgres vì dễ bị sai lệch ngữ cảnh.
-- Chặn authenticated và anon tự sửa role, is_active hoặc id.
CREATE OR REPLACE FUNCTION public.protect_profile_roles()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller_id uuid;
    v_caller_role text;
    v_jwt_role text;
BEGIN
    -- 1. Chặn tuyệt đối việc thay đổi khóa chính id
    IF (OLD.id IS DISTINCT FROM NEW.id) THEN
        RAISE EXCEPTION 'Quy tắc an toàn: Không thể thay đổi khóa chính id của hồ sơ';
    END IF;

    -- 2. Kiểm tra nếu có sự thay đổi về role hoặc is_active
    IF (OLD.role IS DISTINCT FROM NEW.role) OR (OLD.is_active IS DISTINCT FROM NEW.is_active) THEN
        v_caller_id := auth.uid();
        v_jwt_role := nullif(current_setting('request.jwt.claim.role', true), '');

        -- Cho phép ngữ cảnh đặc quyền hệ thống thực sự: service_role JWT key (từ Backend Server)
        IF v_jwt_role = 'service_role' THEN
            RETURN NEW;
        END IF;

        -- Cho phép console DB nội bộ (psql/Supabase SQL Editor chạy trực tiếp bằng superuser postgres/supabase_admin)
        -- Kiểm tra session_user và bảo đảm không thông qua PostgREST HTTP request
        IF session_user IN ('postgres', 'supabase_admin')
           AND v_jwt_role IS NULL
           AND current_setting('request.method', true) IS NULL THEN
            RETURN NEW;
        END IF;

        -- Nếu gọi qua PostgREST nhưng không có auth.uid() (anon hoặc unauthenticated) -> TỪ CHỐI NGAY
        IF v_caller_id IS NULL THEN
            RAISE EXCEPTION 'Quyền hạn bị từ chối: Ngữ cảnh không xác thực không được phép thay đổi vai trò hoặc trạng thái hoạt động';
        END IF;

        -- Với người dùng đã đăng nhập (authenticated): Bắt buộc hồ sơ người gọi phải là Admin và đang hoạt động
        SELECT role INTO v_caller_role
        FROM public.profiles
        WHERE id = v_caller_id AND is_active = true;

        IF v_caller_role IS NULL OR v_caller_role != 'admin' THEN
            RAISE EXCEPTION 'Quyền hạn bị từ chối: Chỉ Quản trị viên (Admin) mới có quyền thay đổi vai trò (role) hoặc trạng thái hoạt động (is_active)';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_protect_profile_roles ON public.profiles;
CREATE TRIGGER trg_protect_profile_roles
BEFORE UPDATE ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.protect_profile_roles();


-- Trigger 3: Ngăn chặn thay đổi order_items.order_id sau khi tạo (MỤC E)
-- Bảo vệ tính toàn vẹn đơn hàng, ngăn ngừa việc chuyển dịch món ăn giữa các đơn.
CREATE OR REPLACE FUNCTION public.prevent_order_item_order_id_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
    IF OLD.order_id IS DISTINCT FROM NEW.order_id THEN
        RAISE EXCEPTION 'Quy tắc toàn vẹn: Không được phép thay đổi order_id của món ăn đã được tạo (item_id: %)', OLD.id;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_order_item_mutation ON public.order_items;
CREATE TRIGGER trg_prevent_order_item_mutation
BEFORE UPDATE ON public.order_items
FOR EACH ROW
EXECUTE FUNCTION public.prevent_order_item_order_id_mutation();


-- Trigger 4: Tự động tính toán lại tổng tiền orders.total_amount khi order_items thay đổi
-- Đảm bảo tính nhất quán tuyệt đối, loại trừ các món có status = 'cancelled'.
CREATE OR REPLACE FUNCTION public.recalculate_order_total_amount()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_target_order_id uuid;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_target_order_id := OLD.order_id;
    ELSE
        v_target_order_id := NEW.order_id;
    END IF;

    -- Tính lại tổng tiền cho đơn hàng đích
    UPDATE public.orders
    SET total_amount = COALESCE((
        SELECT SUM(subtotal)
        FROM public.order_items
        WHERE order_id = v_target_order_id
          AND status != 'cancelled'
    ), 0),
    updated_at = now()
    WHERE id = v_target_order_id;

    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_recalculate_order_total_amount ON public.order_items;
CREATE TRIGGER trg_recalculate_order_total_amount
AFTER INSERT OR UPDATE OF subtotal, status OR DELETE ON public.order_items
FOR EACH ROW
EXECUTE FUNCTION public.recalculate_order_total_amount();


-- Trigger 5: Tự động khởi tạo hồ sơ (profiles) khi tài khoản Auth mới đăng ký trong auth.users
-- Gán vai trò mặc định an toàn là 'staff', lấy full_name từ raw_user_meta_data hoặc email.
-- Ngăn ngừa việc tài khoản mới không có profile và không thể thao tác trong hệ thống.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_full_name text;
    v_phone text;
BEGIN
    v_full_name := COALESCE(
        nullif(trim(NEW.raw_user_meta_data->>'full_name'), ''),
        nullif(trim(NEW.raw_user_meta_data->>'name'), ''),
        nullif(split_part(NEW.email, '@', 1), ''),
        'Nhân viên mới'
    );

    v_phone := COALESCE(
        nullif(trim(NEW.phone), ''),
        nullif(trim(NEW.raw_user_meta_data->>'phone'), '')
    );

    INSERT INTO public.profiles (id, full_name, role, phone, is_active)
    VALUES (
        NEW.id,
        v_full_name,
        'staff', -- Vai trò mặc định an toàn cho nhân sự mới đăng ký
        v_phone,
        true
    )
    ON CONFLICT (id) DO NOTHING;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_user();

-- ------------------------------------------------------------------------------
-- 11. HÀM NỘI BỘ: SINH MÃ ĐƠN HÀNG AN TOÀN CONCURRENCY
-- ------------------------------------------------------------------------------
-- Định dạng: ORD-YYYYMMDD-001 (Ví dụ: ORD-20261018-001)
-- Sử dụng múi giờ Việt Nam (UTC+7 / Asia/Ho_Chi_Minh) cố định phía Server.
-- Khóa hàng nguyên tử với ON CONFLICT (order_date) DO UPDATE trên bảng order_counters.
CREATE OR REPLACE FUNCTION public.generate_order_code()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_today date;
    v_seq int;
    v_order_code text;
BEGIN
    -- Múi giờ chuẩn nghiệp vụ F&B tại Việt Nam (UTC+7)
    v_today := (now() AT TIME ZONE 'Asia/Ho_Chi_Minh')::date;

    -- Khóa hàng nguyên tử với ON CONFLICT DO UPDATE
    INSERT INTO public.order_counters (order_date, last_seq)
    VALUES (v_today, 1)
    ON CONFLICT (order_date) DO UPDATE
    SET last_seq = public.order_counters.last_seq + 1
    RETURNING last_seq INTO v_seq;

    -- Sinh chuỗi mã đơn chuẩn, số thứ tự pad tối thiểu 3 chữ số
    v_order_code := 'ORD-' || to_char(v_today, 'YYYYMMDD') || '-' || lpad(v_seq::text, 3, '0');
    RETURN v_order_code;
END;
$$;

-- ------------------------------------------------------------------------------
-- 12. HÀM NỘI BỘ: ĐỒNG BỘ HOÀN TẤT ĐƠN HÀNG (ORDER COMPLETION ENGINE)
-- ------------------------------------------------------------------------------
-- Kiểm tra điều kiện hoàn tất đơn hàng:
-- Đơn chỉ chuyển sang 'completed' NẾU VÀ CHỈ NẾU:
-- 1. Đơn hàng đã thanh toán đủ (payment_status = 'paid').
-- 2. Toàn bộ món trong đơn đã ở trạng thái kết thúc ('served' hoặc 'cancelled').
CREATE OR REPLACE FUNCTION public.check_and_update_order_completion(p_order_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_order_status text;
    v_payment_status text;
    v_incomplete_items int;
BEGIN
    SELECT status, payment_status
    INTO v_order_status, v_payment_status
    FROM public.orders
    WHERE id = p_order_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN NULL;
    END IF;

    -- Không can thiệp nếu đơn đã hủy hoặc đã hoàn tất trước đó
    IF v_order_status IN ('completed', 'cancelled') THEN
        RETURN v_order_status;
    END IF;

    -- Đơn chỉ được hoàn tất khi đã thanh toán đầy đủ
    IF v_payment_status = 'paid' THEN
        -- Đếm các món chưa phục vụ xong và chưa bị hủy
        SELECT count(*)
        INTO v_incomplete_items
        FROM public.order_items
        WHERE order_id = p_order_id
          AND status NOT IN ('served', 'cancelled');

        IF v_incomplete_items = 0 THEN
            UPDATE public.orders
            SET status = 'completed',
                updated_at = now()
            WHERE id = p_order_id;
            RETURN 'completed';
        END IF;
    END IF;

    RETURN v_order_status;
END;
$$;

-- ------------------------------------------------------------------------------
-- 13. RPC FUNCTIONS NGHIỆP VỤ (TRANSACTIONS CÓ PHÂN CẤP KHÓA)
-- ------------------------------------------------------------------------------

-- ------------------------------------------------------------------------------
-- 13. TIỆN ÍCH QUẢN TRỊ NỘI BỘ: CHỈ ĐỊNH VAI TRÒ ADMIN (CHỈ DÀNH CHO DBA / SQL EDITOR)
-- ------------------------------------------------------------------------------
-- QUY TẮC AN TOÀN TUYỆT ĐỐI:
-- 1. Loại bỏ hoàn toàn RPC claim_first_admin() khỏi client API để triệt tiêu bề mặt tấn công.
-- 2. Chỉ DBA chạy trực tiếp trong Supabase SQL Editor (session_user = postgres/supabase_admin)
--    hoặc Backend Server (service_role) mới có thể thực thi hàm này.
-- 3. Quyền thực thi hàm này bị THU HỒI HOÀN TOÀN từ PUBLIC, anon và authenticated.
DROP FUNCTION IF EXISTS public.claim_first_admin();
DROP FUNCTION IF EXISTS public.claim_first_admin(text);
DROP FUNCTION IF EXISTS public.assign_admin_role(text);

CREATE OR REPLACE FUNCTION public.assign_admin_role(p_target_email text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_user_id uuid;
    v_target_name text;
    v_jwt_role text;
BEGIN
    v_jwt_role := nullif(current_setting('request.jwt.claim.role', true), '');

    -- Kiểm tra quyền: Chỉ cho phép DBA nội bộ qua console/psql hoặc service_role từ backend
    IF session_user NOT IN ('postgres', 'supabase_admin') AND v_jwt_role != 'service_role' THEN
        RAISE EXCEPTION 'Quyền hạn bị từ chối: Hàm chỉ dành riêng cho Quản trị viên cơ sở dữ liệu qua SQL Editor hoặc Backend Service Role';
    END IF;

    -- Tìm người dùng trong auth.users
    SELECT id INTO v_user_id
    FROM auth.users
    WHERE lower(trim(email)) = lower(trim(p_target_email));

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Không tìm thấy tài khoản với email "%" trong auth.users. Vui lòng đăng ký tài khoản trước', p_target_email;
    END IF;

    -- Cập nhật vai trò thành admin
    UPDATE public.profiles
    SET role = 'admin',
        is_active = true,
        updated_at = now()
    WHERE id = v_user_id
    RETURNING full_name INTO v_target_name;

    IF NOT FOUND THEN
        INSERT INTO public.profiles (id, full_name, role, is_active)
        VALUES (
            v_user_id,
            COALESCE(nullif(trim(v_target_name), ''), nullif(split_part(trim(p_target_email), '@', 1), ''), 'Quản trị viên'),
            'admin',
            true
        );
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'user_id', v_user_id,
        'email', p_target_email,
        'role', 'admin',
        'message', 'Đã cấp quyền Quản trị viên (Admin) thành công'
    );
END;
$$;


-- RPC 1: create_full_order (MỤC D & E)
-- Mở đơn hàng mới tại bàn trống.
-- Thứ tự khóa: dining_tables (FOR UPDATE) -> orders (INSERT) -> products (FOR SHARE) -> order_items (INSERT).
CREATE OR REPLACE FUNCTION public.create_full_order(
    p_table_id uuid,
    p_items jsonb,
    p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller_id uuid;
    v_caller_role text;
    v_table_status text;
    v_active_orders_count int;
    v_order_id uuid;
    v_order_code text;
    v_item jsonb;
    v_product_id uuid;
    v_quantity int;
    v_item_notes text;
    v_product_name text;
    v_product_price numeric(12, 2);
    v_product_station text;
    v_product_available boolean;
    v_subtotal numeric(12, 2);
    v_final_total numeric(12, 2);
BEGIN
    -- 1. Bắt buộc người dùng phải xác thực (auth.uid() IS NOT NULL)
    v_caller_id := auth.uid();
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'Yêu cầu xác thực: Người dùng chưa đăng nhập hệ thống';
    END IF;

    SELECT role INTO v_caller_role
    FROM public.profiles
    WHERE id = v_caller_id AND is_active = true;

    IF v_caller_role IS NULL THEN
        RAISE EXCEPTION 'Hồ sơ người dùng không tồn tại hoặc tài khoản đã bị vô hiệu hóa';
    END IF;

    IF v_caller_role NOT IN ('admin', 'staff') THEN
        RAISE EXCEPTION 'Quyền hạn không hợp lệ: Chỉ Quản trị viên hoặc Nhân viên phục vụ mới được phép tạo đơn (vai trò hiện tại: %)', v_caller_role;
    END IF;

    -- 2. Khóa bàn ăn (FOR UPDATE) và kiểm tra tính hợp lệ
    SELECT status INTO v_table_status
    FROM public.dining_tables
    WHERE id = p_table_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Bàn ăn không tồn tại trong hệ thống (table_id: %)', p_table_id;
    END IF;

    IF v_table_status = 'reserved' THEN
        RAISE EXCEPTION 'Bàn đang ở trạng thái đặt trước (reserved), vui lòng kiểm tra lại với quản lý trước khi mở đơn';
    END IF;

    IF v_table_status != 'available' THEN
        RAISE EXCEPTION 'Không thể mở đơn mới: Bàn ăn hiện không ở trạng thái trống (trạng thái hiện tại: %)', v_table_status;
    END IF;

    -- Kiểm tra xem bàn có đơn hàng nào đang hoạt động (pending / in_progress) không
    SELECT count(*) INTO v_active_orders_count
    FROM public.orders
    WHERE table_id = p_table_id
      AND status IN ('pending', 'in_progress');

    IF v_active_orders_count > 0 THEN
        RAISE EXCEPTION 'Bàn ăn hiện đang có đơn hàng chưa hoàn tất. Vui lòng thanh toán hoặc đóng đơn cũ trước khi mở đơn mới tại bàn này';
    END IF;

    -- 3. Xác thực mảng JSON danh sách món đầu vào
    IF p_items IS NULL OR jsonb_typeof(p_items) != 'array' OR jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'Danh sách món đặt không được để trống và phải là mảng JSON hợp lệ';
    END IF;

    -- 4. Sinh mã đơn hàng an toàn concurrency
    v_order_code := public.generate_order_code();

    -- 5. Tạo bản ghi đơn hàng chính (orders)
    INSERT INTO public.orders (
        order_code,
        table_id,
        staff_id,
        status,
        payment_status,
        total_amount,
        notes
    ) VALUES (
        v_order_code,
        p_table_id,
        v_caller_id,
        'pending',
        'unpaid',
        0,
        p_notes
    ) RETURNING id INTO v_order_id;

    -- 6. Lặp qua mảng món đặt và tạo chi tiết (order_items)
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        IF jsonb_typeof(v_item) != 'object' THEN
            RAISE EXCEPTION 'Phần tử trong danh sách món phải là một JSON object hợp lệ';
        END IF;

        IF NOT (v_item ? 'product_id') OR v_item->>'product_id' IS NULL OR length(trim(v_item->>'product_id')) = 0 THEN
            RAISE EXCEPTION 'Chi tiết món bị thiếu hoặc sai định dạng trường product_id';
        END IF;

        BEGIN
            v_product_id := (v_item->>'product_id')::uuid;
        EXCEPTION WHEN invalid_text_representation THEN
            RAISE EXCEPTION 'Mã sản phẩm product_id không đúng định dạng UUID: %', v_item->>'product_id';
        END;

        IF NOT (v_item ? 'quantity') OR v_item->>'quantity' IS NULL THEN
            RAISE EXCEPTION 'Chi tiết món bị thiếu trường quantity (product_id: %)', v_product_id;
        END IF;

        IF (v_item->>'quantity') !~ '^[0-9]+$' THEN
            RAISE EXCEPTION 'Số lượng món phải là số nguyên dương hợp lệ: %', v_item->>'quantity';
        END IF;

        v_quantity := (v_item->>'quantity')::int;

        IF v_quantity <= 0 OR v_quantity > 100 THEN
            RAISE EXCEPTION 'Số lượng món không hợp lệ (%): Số lượng phải nằm trong khoảng từ 1 đến 100 cho mỗi món', v_quantity;
        END IF;

        v_item_notes := v_item->>'notes';

        -- Khóa dòng sản phẩm (FOR SHARE) để bảo đảm tính nhất quán của giá và tình trạng phục vụ
        SELECT name, price, station, is_available
        INTO v_product_name, v_product_price, v_product_station, v_product_available
        FROM public.products
        WHERE id = v_product_id
        FOR SHARE;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Mã sản phẩm không tồn tại trong thực đơn: %', v_product_id;
        END IF;

        IF NOT v_product_available THEN
            RAISE EXCEPTION 'Món "%" hiện đang tạm ngưng phục vụ, không thể đặt món', v_product_name;
        END IF;

        v_subtotal := v_product_price * v_quantity;

        INSERT INTO public.order_items (
            order_id,
            product_id,
            item_name,
            unit_price,
            quantity,
            subtotal,
            notes,
            station,
            status
        ) VALUES (
            v_order_id,
            v_product_id,
            v_product_name,
            v_product_price,
            v_quantity,
            v_subtotal,
            v_item_notes,
            v_product_station,
            'pending'
        );
    END LOOP;

    -- 7. Cập nhật trạng thái bàn sang 'occupied'
    UPDATE public.dining_tables
    SET status = 'occupied',
        updated_at = now()
    WHERE id = p_table_id;

    -- 8. Lấy tổng tiền sau khi trigger recalculate_order_total_amount đã thực thi
    SELECT total_amount INTO v_final_total
    FROM public.orders
    WHERE id = v_order_id;

    -- 9. Trả về kết quả JSON cho Client
    RETURN jsonb_build_object(
        'success', true,
        'order_id', v_order_id,
        'order_code', v_order_code,
        'table_id', p_table_id,
        'total_amount', v_final_total,
        'status', 'pending',
        'payment_status', 'unpaid',
        'item_count', jsonb_array_length(p_items)
    );
END;
$$;


-- RPC 2: add_items_to_order (MỤC D — GỌI THÊM MÓN VÀO ĐƠN HIỆN CÓ)
-- Cho phép khách gọi thêm món vào đơn đang mở tại bàn thay vì mở đơn chồng chéo.
CREATE OR REPLACE FUNCTION public.add_items_to_order(
    p_order_id uuid,
    p_items jsonb,
    p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller_id uuid;
    v_caller_role text;
    v_order RECORD;
    v_item jsonb;
    v_product_id uuid;
    v_quantity int;
    v_item_notes text;
    v_product_name text;
    v_product_price numeric(12, 2);
    v_product_station text;
    v_product_available boolean;
    v_subtotal numeric(12, 2);
    v_final_total numeric(12, 2);
    v_paid_so_far numeric(12, 2);
    v_new_payment_status text;
BEGIN
    -- 1. Xác thực người dùng
    v_caller_id := auth.uid();
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'Yêu cầu xác thực: Người dùng chưa đăng nhập hệ thống';
    END IF;

    SELECT role INTO v_caller_role
    FROM public.profiles
    WHERE id = v_caller_id AND is_active = true;

    IF v_caller_role IS NULL OR v_caller_role NOT IN ('admin', 'staff') THEN
        RAISE EXCEPTION 'Quyền hạn không hợp lệ: Chỉ Quản trị viên hoặc Nhân viên phục vụ mới được gọi thêm món';
    END IF;

    -- 2. Khóa dòng đơn hàng (FOR UPDATE) - Chống race condition với process_payment
    SELECT id, table_id, status, payment_status, total_amount
    INTO v_order
    FROM public.orders
    WHERE id = p_order_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Đơn hàng không tồn tại (order_id: %)', p_order_id;
    END IF;

    IF v_order.status IN ('completed', 'cancelled') THEN
        RAISE EXCEPTION 'Không thể gọi thêm món cho đơn hàng đã hoàn tất hoặc đã bị hủy';
    END IF;

    -- Kiểm tra số tiền đã thanh toán hoàn tất thực tế trước khi thêm món
    SELECT COALESCE(SUM(amount), 0)
    INTO v_paid_so_far
    FROM public.payments
    WHERE order_id = p_order_id AND status = 'completed';

    IF v_order.payment_status = 'paid' OR (v_paid_so_far >= v_order.total_amount AND v_order.total_amount > 0) THEN
        RAISE EXCEPTION 'Đơn hàng đã thanh toán đủ tiền (% / % đ). Vui lòng mở lượt phục vụ mới hoặc điều chỉnh thanh toán trước', v_paid_so_far, v_order.total_amount;
    END IF;

    -- 3. Xác thực mảng JSON
    IF p_items IS NULL OR jsonb_typeof(p_items) != 'array' OR jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'Danh sách món gọi thêm không được để trống';
    END IF;

    -- 4. Chèn chi tiết món mới
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        IF jsonb_typeof(v_item) != 'object' THEN
            RAISE EXCEPTION 'Phần tử trong danh sách món phải là JSON object';
        END IF;

        BEGIN
            v_product_id := (v_item->>'product_id')::uuid;
        EXCEPTION WHEN invalid_text_representation THEN
            RAISE EXCEPTION 'Mã sản phẩm product_id không đúng định dạng UUID: %', v_item->>'product_id';
        END;

        IF (v_item->>'quantity') !~ '^[0-9]+$' THEN
            RAISE EXCEPTION 'Số lượng món phải là số nguyên dương hợp lệ';
        END IF;

        v_quantity := (v_item->>'quantity')::int;
        IF v_quantity <= 0 OR v_quantity > 100 THEN
            RAISE EXCEPTION 'Số lượng món phải từ 1 đến 100';
        END IF;

        v_item_notes := v_item->>'notes';

        SELECT name, price, station, is_available
        INTO v_product_name, v_product_price, v_product_station, v_product_available
        FROM public.products
        WHERE id = v_product_id
        FOR SHARE;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Món không tồn tại: %', v_product_id;
        END IF;

        IF NOT v_product_available THEN
            RAISE EXCEPTION 'Món "%" hiện đang tạm ngưng phục vụ', v_product_name;
        END IF;

        v_subtotal := v_product_price * v_quantity;

        INSERT INTO public.order_items (
            order_id,
            product_id,
            item_name,
            unit_price,
            quantity,
            subtotal,
            notes,
            station,
            status
        ) VALUES (
            p_order_id,
            v_product_id,
            v_product_name,
            v_product_price,
            v_quantity,
            v_subtotal,
            v_item_notes,
            v_product_station,
            'pending'
        );
    END LOOP;

    -- 5. Lấy tổng tiền sau khi trigger recalculate_order_total_amount thực thi
    SELECT total_amount INTO v_final_total
    FROM public.orders
    WHERE id = p_order_id;

    -- 6. Cập nhật trạng thái thanh toán nhất quán từ tổng tiền mới và số tiền đã thanh toán
    IF v_paid_so_far = 0 THEN
        v_new_payment_status := 'unpaid';
    ELSIF v_paid_so_far < v_final_total THEN
        v_new_payment_status := 'partially_paid';
    ELSE
        v_new_payment_status := 'paid';
    END IF;

    UPDATE public.orders
    SET payment_status = v_new_payment_status,
        updated_at = now()
    WHERE id = p_order_id;

    RETURN jsonb_build_object(
        'success', true,
        'order_id', p_order_id,
        'added_items_count', jsonb_array_length(p_items),
        'new_total_amount', v_final_total,
        'paid_so_far', v_paid_so_far,
        'remaining_balance', (v_final_total - v_paid_so_far),
        'payment_status', v_new_payment_status
    );
END;
$$;


-- RPC 3: process_payment (MỤC C & E)
-- Ghi nhận thanh toán an toàn với kiểm tra số thập phân, chống thanh toán lặp, khóa orders (FOR UPDATE).
CREATE OR REPLACE FUNCTION public.process_payment(
    p_order_id uuid,
    p_amount numeric,
    p_payment_method text DEFAULT 'cash',
    p_transaction_code text DEFAULT NULL,
    p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller_id uuid;
    v_caller_role text;
    v_order RECORD;
    v_paid_so_far numeric(12, 2);
    v_remaining_balance numeric(12, 2);
    v_clean_txn_code text;
    v_payment_id uuid;
    v_new_paid_total numeric(12, 2);
    v_new_payment_status text;
    v_final_order_status text;
BEGIN
    -- 1. Bắt buộc người dùng phải xác thực (auth.uid() IS NOT NULL)
    v_caller_id := auth.uid();
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'Yêu cầu xác thực: Người dùng chưa đăng nhập hệ thống';
    END IF;

    SELECT role INTO v_caller_role
    FROM public.profiles
    WHERE id = v_caller_id AND is_active = true;

    IF v_caller_role IS NULL OR v_caller_role NOT IN ('admin', 'staff') THEN
        RAISE EXCEPTION 'Quyền hạn không hợp lệ: Chỉ Quản trị viên hoặc Nhân viên phục vụ mới được xử lý thanh toán';
    END IF;

    -- 2. Kiểm tra phương thức và số tiền thanh toán (chính xác 2 chữ số thập phân - MỤC C)
    IF p_payment_method NOT IN ('cash', 'banking_qr', 'card') THEN
        RAISE EXCEPTION 'Phương thức thanh toán không hợp lệ: % (chỉ chấp nhận: cash, banking_qr, card)', p_payment_method;
    END IF;

    IF p_amount IS NULL OR p_amount <= 0 OR round(p_amount, 2) != p_amount THEN
        RAISE EXCEPTION 'Số tiền thanh toán phải lớn hơn 0 và chỉ có tối đa 2 chữ số thập phân (số tiền gửi: %)', p_amount;
    END IF;

    -- Chuẩn hóa và kiểm tra mã giao dịch đối soát (chống thanh toán lặp - MỤC C)
    v_clean_txn_code := nullif(trim(p_transaction_code), '');

    IF v_clean_txn_code IS NOT NULL THEN
        IF EXISTS (
            SELECT 1 FROM public.payments
            WHERE trim(transaction_code) = v_clean_txn_code
              AND status = 'completed'
        ) THEN
            RAISE EXCEPTION 'Giao dịch với mã đối soát "%" đã tồn tại và đã được xử lý thành công trước đó', v_clean_txn_code;
        END IF;
    END IF;

    -- 3. Khóa dòng đơn hàng với SELECT ... FOR UPDATE theo đúng thứ tự phân cấp
    SELECT id, table_id, total_amount, status, payment_status
    INTO v_order
    FROM public.orders
    WHERE id = p_order_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Đơn hàng không tồn tại trong hệ thống (order_id: %)', p_order_id;
    END IF;

    IF v_order.status = 'cancelled' THEN
        RAISE EXCEPTION 'Không thể thực hiện thanh toán cho đơn hàng đã bị hủy';
    END IF;

    IF v_order.payment_status = 'paid' THEN
        RAISE EXCEPTION 'Đơn hàng này đã được thanh toán hoàn tất trước đó';
    END IF;

    -- 4. Tính toán số tiền đã thanh toán thành công trước đây
    SELECT COALESCE(SUM(amount), 0)
    INTO v_paid_so_far
    FROM public.payments
    WHERE order_id = p_order_id AND status = 'completed';

    v_remaining_balance := v_order.total_amount - v_paid_so_far;

    IF p_amount > v_remaining_balance THEN
        RAISE EXCEPTION 'Số tiền thanh toán (% đ) vượt quá số tiền còn lại phải trả (% đ)', p_amount, v_remaining_balance;
    END IF;

    -- 5. Ghi nhận bản ghi thanh toán
    INSERT INTO public.payments (
        order_id,
        amount,
        payment_method,
        status,
        transaction_code,
        processed_by,
        notes
    ) VALUES (
        p_order_id,
        p_amount,
        p_payment_method,
        'completed',
        v_clean_txn_code,
        v_caller_id,
        p_notes
    ) RETURNING id INTO v_payment_id;

    -- 6. Cập nhật trạng thái thanh toán của đơn hàng
    v_new_paid_total := v_paid_so_far + p_amount;

    IF v_new_paid_total >= v_order.total_amount THEN
        v_new_payment_status := 'paid';
    ELSE
        v_new_payment_status := 'partially_paid';
    END IF;

    UPDATE public.orders
    SET payment_status = v_new_payment_status,
        updated_at = now()
    WHERE id = p_order_id;

    -- 7. Đồng bộ kiểm tra hoàn tất đơn hàng (orders.status = 'completed')
    v_final_order_status := public.check_and_update_order_completion(p_order_id);

    -- 8. Trả về kết quả
    RETURN jsonb_build_object(
        'success', true,
        'payment_id', v_payment_id,
        'order_id', p_order_id,
        'paid_amount', p_amount,
        'total_amount', v_order.total_amount,
        'remaining_balance', (v_order.total_amount - v_new_paid_total),
        'payment_status', v_new_payment_status,
        'order_status', v_final_order_status
    );
END;
$$;


-- RPC 4: update_order_item_status (MỤC C & E)
-- Khóa dòng theo đúng thứ tự phân cấp: orders (FOR UPDATE) trước, order_items (FOR UPDATE) sau để triệt tiêu deadlock.
-- Chặn hủy món đối với đơn hàng đã phát sinh thanh toán nếu chưa có quy trình hoàn tiền.
CREATE OR REPLACE FUNCTION public.update_order_item_status(
    p_item_id uuid,
    p_new_status text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller_id uuid;
    v_caller_role text;
    v_target_order_id uuid;
    v_item RECORD;
    v_order_status text;
    v_order_pay_status text;
    v_final_order_status text;
BEGIN
    -- 1. Bắt buộc người dùng phải xác thực (auth.uid() IS NOT NULL)
    v_caller_id := auth.uid();
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'Yêu cầu xác thực: Người dùng chưa đăng nhập hệ thống';
    END IF;

    SELECT role INTO v_caller_role
    FROM public.profiles
    WHERE id = v_caller_id AND is_active = true;

    IF v_caller_role IS NULL THEN
        RAISE EXCEPTION 'Hồ sơ người dùng không tồn tại hoặc tài khoản đã bị vô hiệu hóa';
    END IF;

    -- 2. Kiểm tra giá trị trạng thái mới hợp lệ
    IF p_new_status NOT IN ('pending', 'preparing', 'ready', 'served', 'cancelled') THEN
        RAISE EXCEPTION 'Trạng thái món không hợp lệ: %', p_new_status;
    END IF;

    -- 3. Xác định order_id của món
    SELECT order_id INTO v_target_order_id
    FROM public.order_items
    WHERE id = p_item_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Chi tiết món không tồn tại (item_id: %)', p_item_id;
    END IF;

    -- 4. THỨ TỰ PHÂN CẤP KHÓA (MỤC E): Khóa cha orders (FOR UPDATE) trước
    SELECT status, payment_status
    INTO v_order_status, v_order_pay_status
    FROM public.orders
    WHERE id = v_target_order_id
    FOR UPDATE;

    IF v_order_status = 'cancelled' THEN
        RAISE EXCEPTION 'Không thể cập nhật món trong đơn hàng đã bị hủy';
    END IF;

    IF v_order_status = 'completed' THEN
        RAISE EXCEPTION 'Đơn hàng đã hoàn tất (completed). Không thể tiếp tục thay đổi trạng thái món';
    END IF;

    -- 5. THỨ TỰ PHÂN CẤP KHÓA: Khóa con order_items (FOR UPDATE) sau
    SELECT id, order_id, station, status
    INTO v_item
    FROM public.order_items
    WHERE id = p_item_id
    FOR UPDATE;

    -- Nếu trạng thái không thay đổi, trả về kết quả ngay
    IF v_item.status = p_new_status THEN
        RETURN jsonb_build_object(
            'success', true,
            'item_id', p_item_id,
            'order_id', v_item.order_id,
            'old_status', v_item.status,
            'new_status', p_new_status,
            'message', 'Trạng thái món không đổi'
        );
    END IF;

    -- Các trạng thái kết thúc (served, cancelled) không thể bị chuyển đổi tiếp
    IF v_item.status IN ('served', 'cancelled') THEN
        RAISE EXCEPTION 'Món ăn đã ở trạng thái kết thúc (%) không thể thay đổi trạng thái', v_item.status;
    END IF;

    -- Chặn hủy món đối với đơn đã thanh toán để tránh làm sai lệch số dư (MỤC C)
    IF p_new_status = 'cancelled' AND v_order_pay_status IN ('paid', 'partially_paid') THEN
        RAISE EXCEPTION 'Không thể hủy món trong đơn hàng đã phát sinh thanh toán (%). Hệ thống hiện chưa có quy trình ghi nhận hoàn tiền tự động', v_order_pay_status;
    END IF;

    -- 6. Kiểm tra ma trận phân quyền và chuyển trạng thái cũ -> mới nghiêm ngặt
    CASE v_caller_role
        -- Vai trò Bếp (Kitchen): chỉ xử lý món station = 'kitchen'
        WHEN 'kitchen' THEN
            IF v_item.station != 'kitchen' THEN
                RAISE EXCEPTION 'Nhân viên Bếp chỉ có quyền thao tác với món ăn thuộc trạm Bếp (kitchen)';
            END IF;
            IF NOT (
                (v_item.status = 'pending' AND p_new_status = 'preparing') OR
                (v_item.status = 'preparing' AND p_new_status = 'ready')
            ) THEN
                RAISE EXCEPTION 'Nhân viên Bếp không được phép chuyển trạng thái món từ "%" sang "%"', v_item.status, p_new_status;
            END IF;

        -- Vai trò Bar: chỉ xử lý đồ uống station = 'bar'
        WHEN 'bar' THEN
            IF v_item.station != 'bar' THEN
                RAISE EXCEPTION 'Nhân viên Bar chỉ có quyền thao tác với đồ uống thuộc trạm Bar (bar)';
            END IF;
            IF NOT (
                (v_item.status = 'pending' AND p_new_status = 'preparing') OR
                (v_item.status = 'preparing' AND p_new_status = 'ready')
            ) THEN
                RAISE EXCEPTION 'Nhân viên Bar không được phép chuyển trạng thái đồ uống từ "%" sang "%"', v_item.status, p_new_status;
            END IF;

        -- Vai trò Phục vụ (Staff): bưng món (ready -> served) hoặc hủy món (pending -> cancelled)
        WHEN 'staff' THEN
            IF (v_item.status = 'ready' AND p_new_status = 'served') THEN
                NULL;
            ELSIF (v_item.status = 'pending' AND p_new_status = 'cancelled') THEN
                NULL;
            ELSIF (v_item.status = 'preparing' AND p_new_status = 'cancelled') THEN
                RAISE EXCEPTION 'Món đang trong quá trình chế biến (preparing). Cần sự xác nhận của Bếp/Bar hoặc Quản trị viên để hủy';
            ELSE
                RAISE EXCEPTION 'Nhân viên Phục vụ không có quyền chuyển trạng thái món từ "%" sang "%"', v_item.status, p_new_status;
            END IF;

        -- Vai trò Quản trị viên (Admin): được duyệt mọi bước chuyển hợp lệ
        WHEN 'admin' THEN
            IF NOT (
                (v_item.status = 'pending' AND p_new_status IN ('preparing', 'cancelled')) OR
                (v_item.status = 'preparing' AND p_new_status IN ('ready', 'cancelled')) OR
                (v_item.status = 'ready' AND p_new_status IN ('served', 'cancelled'))
            ) THEN
                RAISE EXCEPTION 'Chuyển đổi trạng thái từ "%" sang "%" không hợp lệ theo quy trình', v_item.status, p_new_status;
            END IF;

        ELSE
            RAISE EXCEPTION 'Vai trò người dùng không hợp lệ (%)', v_caller_role;
    END CASE;

    -- 7. Cập nhật trạng thái món
    UPDATE public.order_items
    SET status = p_new_status,
        updated_at = now()
    WHERE id = p_item_id;

    -- 8. Nếu đơn đang 'pending' mà có món chuyển sang 'preparing' hoặc 'ready' -> tự động đổi đơn sang 'in_progress'
    IF v_order_status = 'pending' AND p_new_status IN ('preparing', 'ready') THEN
        UPDATE public.orders
        SET status = 'in_progress',
            updated_at = now()
        WHERE id = v_item.order_id;
        v_order_status := 'in_progress';
    END IF;

    -- 9. Đồng bộ kiểm tra hoàn tất đơn hàng (Bảo đảm hoàn tất nếu đã thanh toán đủ và hết món dở dang)
    v_final_order_status := public.check_and_update_order_completion(v_item.order_id);

    RETURN jsonb_build_object(
        'success', true,
        'item_id', p_item_id,
        'order_id', v_item.order_id,
        'old_status', v_item.status,
        'new_status', p_new_status,
        'order_status', v_final_order_status
    );
END;
$$;


-- RPC 5: release_dining_table (MỤC B & D)
-- Giải phóng bàn ăn thủ công sau khi khách rời đi và nhân viên đã dọn dẹp bàn xong.
-- Ngăn chặn giải phóng bàn nếu vẫn còn đơn hàng chưa hoàn tất.
CREATE OR REPLACE FUNCTION public.release_dining_table(p_table_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller_id uuid;
    v_caller_role text;
    v_table_status text;
    v_active_order_count int;
BEGIN
    v_caller_id := auth.uid();
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'Yêu cầu xác thực: Người dùng chưa đăng nhập hệ thống';
    END IF;

    SELECT role INTO v_caller_role
    FROM public.profiles
    WHERE id = v_caller_id AND is_active = true;

    IF v_caller_role IS NULL OR v_caller_role NOT IN ('admin', 'staff') THEN
        RAISE EXCEPTION 'Quyền hạn bị từ chối: Chỉ Quản trị viên hoặc Nhân viên phục vụ mới có quyền giải phóng bàn';
    END IF;

    SELECT status INTO v_table_status
    FROM public.dining_tables
    WHERE id = p_table_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Bàn ăn không tồn tại trong hệ thống (table_id: %)', p_table_id;
    END IF;

    -- Xử lý an toàn Idempotent: Nếu bàn đã ở trạng thái available thì trả về kết quả thành công ngay
    IF v_table_status = 'available' THEN
        RETURN jsonb_build_object(
            'success', true,
            'table_id', p_table_id,
            'status', 'available',
            'message', 'Bàn ăn hiện đã ở trạng thái trống'
        );
    END IF;

    -- Chặn giải phóng bàn đang ở trạng thái đặt trước (reserved)
    -- Quy tắc nghiệp vụ: Bàn đặt trước không thể bị giải phóng qua release_dining_table (kể cả Staff và Admin).
    -- Việc tiếp nhận khách hoặc hủy đặt trước phải được thực hiện qua quy trình quản lý đặt bàn riêng.
    IF v_table_status = 'reserved' THEN
        RAISE EXCEPTION 'Không thể giải phóng bàn: Bàn đang ở trạng thái đặt trước (reserved). Thao tác hủy hoặc tiếp nhận bàn đặt trước cần được thực hiện qua quy trình quản lý đặt bàn riêng';
    END IF;

    -- Kiểm tra xem còn đơn hàng nào chưa hoàn tất tại bàn này không
    SELECT count(*) INTO v_active_order_count
    FROM public.orders
    WHERE table_id = p_table_id
      AND status IN ('pending', 'in_progress');

    IF v_active_order_count > 0 THEN
        RAISE EXCEPTION 'Không thể giải phóng bàn: Vẫn còn % đơn hàng chưa hoàn tất tại bàn này', v_active_order_count;
    END IF;

    UPDATE public.dining_tables
    SET status = 'available',
        updated_at = now()
    WHERE id = p_table_id;

    RETURN jsonb_build_object(
        'success', true,
        'table_id', p_table_id,
        'status', 'available',
        'message', 'Đã dọn dẹp và giải phóng bàn thành công'
    );
END;
$$;

-- ------------------------------------------------------------------------------
-- 14. ROW LEVEL SECURITY (RLS) POLICIES
-- ------------------------------------------------------------------------------

-- Helper function lấy vai trò người dùng hiện tại an toàn
CREATE OR REPLACE FUNCTION public.current_user_role()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT role FROM public.profiles WHERE id = auth.uid() AND is_active = true;
$$;

-- Kích hoạt RLS trên toàn bộ 8 bảng (7 bảng nghiệp vụ + 1 bảng bộ đếm)
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dining_tables ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_counters ENABLE ROW LEVEL SECURITY;

-- 14.1. RLS cho bảng PROFILES
-- Người dùng xem hồ sơ của mình; Admin xem toàn bộ hồ sơ.
-- Người dùng thông thường chỉ được sửa hồ sơ của mình nếu is_active = true (trigger sẽ chặn sửa role/is_active/id).
DROP POLICY IF EXISTS profiles_select_policy ON public.profiles;
CREATE POLICY profiles_select_policy ON public.profiles
    FOR SELECT TO authenticated
    USING (auth.uid() = id OR public.current_user_role() = 'admin');

DROP POLICY IF EXISTS profiles_update_policy ON public.profiles;
CREATE POLICY profiles_update_policy ON public.profiles
    FOR UPDATE TO authenticated
    USING ((auth.uid() = id AND is_active = true) OR public.current_user_role() = 'admin')
    WITH CHECK ((auth.uid() = id AND is_active = true) OR public.current_user_role() = 'admin');

-- 14.2. RLS cho bảng CATEGORIES
DROP POLICY IF EXISTS categories_select_policy ON public.categories;
CREATE POLICY categories_select_policy ON public.categories
    FOR SELECT TO authenticated
    USING (true);

-- 14.3. RLS cho bảng PRODUCTS
DROP POLICY IF EXISTS products_select_policy ON public.products;
CREATE POLICY products_select_policy ON public.products
    FOR SELECT TO authenticated
    USING (true);

-- 14.4. RLS cho bảng DINING_TABLES (MỤC B — CHỈ XEM, KHÔNG CHO STAFF SỬA TRỰC TIẾP)
-- Staff và Admin chỉ có quyền SELECT để xem sơ đồ bàn. Mọi cập nhật trạng thái bàn buộc phải qua RPC.
DROP POLICY IF EXISTS dining_tables_select_policy ON public.dining_tables;
CREATE POLICY dining_tables_select_policy ON public.dining_tables
    FOR SELECT TO authenticated
    USING (true);

-- 14.5. RLS cho bảng ORDERS (MỤC B — ZERO DIRECT WRITE)
-- Toàn bộ authenticated chỉ có quyền SELECT. Mọi thao tác ghi buộc qua RPC create_full_order / add_items_to_order / process_payment.
DROP POLICY IF EXISTS orders_select_policy ON public.orders;
CREATE POLICY orders_select_policy ON public.orders
    FOR SELECT TO authenticated
    USING (true);

-- 14.6. RLS cho bảng ORDER_ITEMS (MỤC B — PHÂN TÁCH TRẠM VÀ ZERO DIRECT WRITE)
-- Kitchen chỉ xem món trạm kitchen; Bar chỉ xem đồ uống trạm bar; Staff/Admin xem tất cả.
-- Không cấp quyền INSERT, UPDATE, DELETE trực tiếp cho bất kỳ ai. Mọi cập nhật buộc qua RPC.
DROP POLICY IF EXISTS order_items_select_policy ON public.order_items;
CREATE POLICY order_items_select_policy ON public.order_items
    FOR SELECT TO authenticated
    USING (
        public.current_user_role() IN ('admin', 'staff')
        OR (public.current_user_role() = 'kitchen' AND station = 'kitchen')
        OR (public.current_user_role() = 'bar' AND station = 'bar')
    );

-- 14.7. RLS cho bảng PAYMENTS (MỤC B — ZERO DIRECT WRITE)
-- Staff và Admin được xem lịch sử thanh toán. Ghi nhận giao dịch bắt buộc qua RPC process_payment.
DROP POLICY IF EXISTS payments_select_policy ON public.payments;
CREATE POLICY payments_select_policy ON public.payments
    FOR SELECT TO authenticated
    USING (public.current_user_role() IN ('admin', 'staff'));

-- 14.8. RLS cho bảng ORDER_COUNTERS
-- Khóa hoàn toàn: Không cấp quyền cho người dùng thông thường, chỉ RPC nội bộ SECURITY DEFINER thao tác.
DROP POLICY IF EXISTS order_counters_deny_all ON public.order_counters;
CREATE POLICY order_counters_deny_all ON public.order_counters
    FOR ALL TO authenticated
    USING (false);

-- ------------------------------------------------------------------------------
-- 15. THIẾT LẬP QUYỀN SQL (GRANT / REVOKE - MỤC B)
-- ------------------------------------------------------------------------------

-- 15.1. Thu hồi toàn bộ quyền từ role 'anon' trên toàn bộ schema public
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM anon;
REVOKE ALL ON ALL ROUTINES IN SCHEMA public FROM anon;

-- 15.2. Thu hồi toàn bộ quyền trực tiếp trên bảng order_counters
REVOKE ALL ON TABLE public.order_counters FROM PUBLIC, anon, authenticated;

-- 15.3. Áp dụng nguyên tắc Zero-Direct-Write: Thu hồi INSERT, UPDATE, DELETE trực tiếp trên bảng nghiệp vụ
REVOKE INSERT, UPDATE, DELETE ON public.orders FROM PUBLIC, anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.order_items FROM PUBLIC, anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.payments FROM PUBLIC, anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.dining_tables FROM PUBLIC, anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.categories FROM PUBLIC, anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.products FROM PUBLIC, anon, authenticated;

-- Cấp quyền SELECT cần thiết cho role 'authenticated'
GRANT SELECT ON public.profiles TO authenticated;
GRANT UPDATE (full_name, phone) ON public.profiles TO authenticated;
GRANT SELECT ON public.categories TO authenticated;
GRANT SELECT ON public.products TO authenticated;
GRANT SELECT ON public.dining_tables TO authenticated;
GRANT SELECT ON public.orders TO authenticated;
GRANT SELECT ON public.order_items TO authenticated;
GRANT SELECT ON public.payments TO authenticated;

-- 15.4. Thu hồi quyền thực thi mặc định trên các hàm nội bộ và trigger không để client gọi trực tiếp
REVOKE ALL ON FUNCTION public.generate_order_code() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.check_and_update_order_completion(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.handle_updated_at() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.protect_profile_roles() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.prevent_order_item_order_id_mutation() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.recalculate_order_total_amount() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.assign_admin_role(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.assign_admin_role(text) TO service_role;

-- 15.5. Thu hồi quyền thực thi từ public/anon trên các RPC nghiệp vụ
REVOKE ALL ON FUNCTION public.create_full_order(uuid, jsonb, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.add_items_to_order(uuid, jsonb, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.process_payment(uuid, numeric, text, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.update_order_item_status(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.release_dining_table(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.current_user_role() FROM PUBLIC, anon;

-- 15.6. Cấp quyền thực thi các RPC nghiệp vụ cho role 'authenticated'
-- Lưu ý: Tuyệt đối KHÔNG cấp quyền assign_admin_role cho authenticated. Chỉ DBA qua SQL Editor mới được gọi.
GRANT EXECUTE ON FUNCTION public.create_full_order(uuid, jsonb, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.add_items_to_order(uuid, jsonb, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.process_payment(uuid, numeric, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_order_item_status(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.release_dining_table(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_user_role() TO authenticated;

-- ------------------------------------------------------------------------------
-- 16. SEED DATA MẪU (IDEMPOTENT / RE-RUN SAFE)
-- ------------------------------------------------------------------------------
-- Tuyệt đối KHÔNG chèn tài khoản Auth, mật khẩu giả hoặc người dùng vào auth.users.

-- 16.1. Danh mục thực đơn chuẩn F&B
INSERT INTO public.categories (name, description, display_order, is_active)
VALUES
    ('Món ăn chính', 'Các món cơm, mì, lẩu và món bò nóng hổi phục vụ tại bàn', 1, true),
    ('Món ăn vặt', 'Khoai tây chiên, đồ ăn nhẹ và món khai vị', 2, true),
    ('Cà phê', 'Cà phê muối, cà phê pha phin và cà phê truyền thống Việt Nam', 3, true),
    ('Trà & Trà sữa', 'Trà đào cam sả, trà trái cây thanh nhiệt và trà sữa', 4, true),
    ('Đá xay & Sinh tố', 'Sinh tố bơ sầu riêng, nước ép và đồ uống giải khát mát lạnh', 5, true)
ON CONFLICT (name) DO UPDATE
SET description = EXCLUDED.description,
    display_order = EXCLUDED.display_order,
    is_active = EXCLUDED.is_active;

-- 16.2. Sản phẩm (Phân loại chính xác giữa 'kitchen' và 'bar', đồng bộ với UI Flutter Demo)
INSERT INTO public.products (category_id, name, description, price, station, is_available)
SELECT c.id, p.name, p.description, p.price, p.station, p.is_available
FROM (VALUES
    -- Món Bếp (Kitchen)
    ('Món ăn chính', 'Bò lúc lắc khoai tây', 'Thịt bò mềm đậm vị xào rau củ tươi kèm khoai tây chiên giòn', 125000.00, 'kitchen', true),
    ('Món ăn chính', 'Cơm sườn nướng', 'Cơm tấm sườn nướng mật ong thơm lừng dùng kèm dưa chua', 65000.00, 'kitchen', true),
    ('Món ăn chính', 'Mì xào hải sản', 'Mì sợi xào mực, tôm tươi và rau cải giòn ngọt', 75000.00, 'kitchen', true),
    ('Món ăn chính', 'Lẩu Thái hải sản', 'Nồi lẩu chua cay đậm đà với tôm, mực, nghêu và rau nấm', 220000.00, 'kitchen', true),
    ('Món ăn vặt', 'Khoai tây chiên bơ tỏi', 'Khoai tây chiên vàng ươm lắc sốt bơ tỏi thơm ngậy', 35000.00, 'kitchen', true),
    ('Món ăn vặt', 'Cánh gà chiên nước mắm', 'Cánh gà giòn rụm ngấm sốt nước mắm chua ngọt', 55000.00, 'kitchen', true),

    -- Món Quầy Pha Chế (Bar)
    ('Trà & Trà sữa', 'Trà đào cam sả', 'Trà thanh mát kết hợp lát đào giòn ngọt và hương sả nồng nàn', 35000.00, 'bar', true),
    ('Cà phê', 'Cà phê muối', 'Cà phê pha phin đậm đặc phủ lớp kem muối béo ngậy đặc trưng', 28000.00, 'bar', true),
    ('Cà phê', 'Cà phê đen đá', 'Cà phê Robusta nguyên chất thơm nồng truyền thống', 20000.00, 'bar', true),
    ('Cà phê', 'Cà phê sữa đá', 'Cà phê pha phin hòa quyện cùng sữa đặc béo ngọt', 25000.00, 'bar', true),
    ('Đá xay & Sinh tố', 'Sinh tố bơ sầu riêng', 'Bơ sáp dẻo quánh xay cùng cơm sầu riêng chín cây béo bùi', 45000.00, 'bar', true),
    ('Trà & Trà sữa', 'Nước ngọt Coca/Pepsi', 'Nước ngọt có gas ướp lạnh lon 330ml', 18000.00, 'bar', true)
) AS p(cat_name, name, description, price, station, is_available)
JOIN public.categories c ON c.name = p.cat_name
WHERE NOT EXISTS (
    SELECT 1 FROM public.products prod WHERE prod.name = p.name
);

-- 16.3. Sơ đồ 12 Bàn ăn (Đồng bộ với Flutter Staff Screen)
INSERT INTO public.dining_tables (name, capacity, area, status)
VALUES
    ('Bàn 01', 4, 'Tầng 1', 'available'),
    ('Bàn 02', 4, 'Tầng 1', 'available'),
    ('Bàn 03', 2, 'Tầng 1', 'available'),
    ('Bàn 04', 6, 'Tầng 1', 'available'),
    ('Bàn 05', 4, 'Tầng 1', 'available'),
    ('Bàn 06', 8, 'Tầng 1', 'available'),
    ('Bàn 07', 4, 'Tầng 2', 'available'),
    ('Bàn 08', 4, 'Tầng 2', 'available'),
    ('Bàn 09', 2, 'Tầng 2', 'available'),
    ('Bàn 10', 6, 'Tầng 2', 'available'),
    ('Bàn 11', 4, 'Tầng 2', 'available'),
    ('Bàn 12', 4, 'Tầng 2', 'available')
ON CONFLICT (name) DO UPDATE
SET capacity = EXCLUDED.capacity,
    area = EXCLUDED.area;

-- Hoàn tất Transaction
COMMIT;
