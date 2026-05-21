
-- 1) Add cashier role
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'cashier';

-- 2) Categories
CREATE TABLE IF NOT EXISTS public.categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL,
  name TEXT NOT NULL,
  color TEXT DEFAULT '#FF7A00',
  icon TEXT,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
CREATE POLICY "members rw categories" ON public.categories FOR ALL TO authenticated
  USING (public.is_company_member(auth.uid(), company_id))
  WITH CHECK (public.is_company_member(auth.uid(), company_id));
CREATE INDEX IF NOT EXISTS idx_categories_company ON public.categories(company_id);

-- 3) Products: add category + barcode
ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS category_id UUID,
  ADD COLUMN IF NOT EXISTS barcode TEXT,
  ADD COLUMN IF NOT EXISTS image_url TEXT;
CREATE INDEX IF NOT EXISTS idx_products_barcode ON public.products(company_id, barcode);
CREATE INDEX IF NOT EXISTS idx_products_category ON public.products(company_id, category_id);

-- 4) Cash registers
CREATE TABLE IF NOT EXISTS public.cash_registers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL,
  name TEXT NOT NULL,
  location TEXT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.cash_registers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "members rw cash_registers" ON public.cash_registers FOR ALL TO authenticated
  USING (public.is_company_member(auth.uid(), company_id))
  WITH CHECK (public.is_company_member(auth.uid(), company_id));

-- 5) POS sessions
CREATE TABLE IF NOT EXISTS public.pos_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL,
  register_id UUID NOT NULL,
  user_id UUID NOT NULL,
  opening_balance NUMERIC NOT NULL DEFAULT 0,
  closing_balance NUMERIC,
  expected_balance NUMERIC,
  difference NUMERIC,
  total_sales NUMERIC NOT NULL DEFAULT 0,
  total_cash NUMERIC NOT NULL DEFAULT 0,
  total_card NUMERIC NOT NULL DEFAULT 0,
  orders_count INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'open',
  notes TEXT,
  opened_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  closed_at TIMESTAMPTZ
);
ALTER TABLE public.pos_sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "members rw pos_sessions" ON public.pos_sessions FOR ALL TO authenticated
  USING (public.is_company_member(auth.uid(), company_id))
  WITH CHECK (public.is_company_member(auth.uid(), company_id));
CREATE INDEX IF NOT EXISTS idx_pos_sessions_company ON public.pos_sessions(company_id, status);
CREATE INDEX IF NOT EXISTS idx_pos_sessions_user ON public.pos_sessions(user_id, status);

-- 6) POS orders
CREATE TABLE IF NOT EXISTS public.pos_orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL,
  session_id UUID NOT NULL,
  order_number TEXT NOT NULL,
  customer_id UUID,
  subtotal NUMERIC NOT NULL DEFAULT 0,
  tax_amount NUMERIC NOT NULL DEFAULT 0,
  discount NUMERIC NOT NULL DEFAULT 0,
  total NUMERIC NOT NULL DEFAULT 0,
  payment_method TEXT NOT NULL DEFAULT 'cash',
  amount_paid NUMERIC NOT NULL DEFAULT 0,
  change_due NUMERIC NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'completed',
  notes TEXT,
  created_by UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.pos_orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "members rw pos_orders" ON public.pos_orders FOR ALL TO authenticated
  USING (public.is_company_member(auth.uid(), company_id))
  WITH CHECK (public.is_company_member(auth.uid(), company_id));
CREATE INDEX IF NOT EXISTS idx_pos_orders_session ON public.pos_orders(session_id);
CREATE INDEX IF NOT EXISTS idx_pos_orders_company_date ON public.pos_orders(company_id, created_at DESC);

-- 7) POS order items
CREATE TABLE IF NOT EXISTS public.pos_order_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL,
  product_id UUID,
  product_name TEXT NOT NULL,
  quantity NUMERIC NOT NULL DEFAULT 1,
  unit_price NUMERIC NOT NULL DEFAULT 0,
  tax_rate NUMERIC NOT NULL DEFAULT 15,
  total NUMERIC NOT NULL DEFAULT 0
);
ALTER TABLE public.pos_order_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "members rw pos_order_items" ON public.pos_order_items FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.pos_orders o WHERE o.id = pos_order_items.order_id AND public.is_company_member(auth.uid(), o.company_id)))
  WITH CHECK (EXISTS (SELECT 1 FROM public.pos_orders o WHERE o.id = pos_order_items.order_id AND public.is_company_member(auth.uid(), o.company_id)));
