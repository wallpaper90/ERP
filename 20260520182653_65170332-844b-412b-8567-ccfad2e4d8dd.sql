
-- Suppliers
CREATE TABLE public.suppliers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL,
  name text NOT NULL,
  phone text, email text, address text, tax_number text, notes text,
  balance numeric NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "members rw suppliers" ON public.suppliers FOR ALL TO authenticated
  USING (is_company_member(auth.uid(), company_id))
  WITH CHECK (is_company_member(auth.uid(), company_id));
CREATE INDEX idx_suppliers_company ON public.suppliers(company_id);

-- Purchases
CREATE TYPE purchase_status AS ENUM ('draft','received','partial','paid','cancelled');
CREATE TABLE public.purchases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL,
  supplier_id uuid,
  invoice_number text NOT NULL,
  invoice_date date NOT NULL DEFAULT CURRENT_DATE,
  subtotal numeric NOT NULL DEFAULT 0,
  tax_amount numeric NOT NULL DEFAULT 0,
  discount numeric NOT NULL DEFAULT 0,
  total numeric NOT NULL DEFAULT 0,
  paid_amount numeric NOT NULL DEFAULT 0,
  status purchase_status NOT NULL DEFAULT 'draft',
  notes text,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.purchases ENABLE ROW LEVEL SECURITY;
CREATE POLICY "members rw purchases" ON public.purchases FOR ALL TO authenticated
  USING (is_company_member(auth.uid(), company_id))
  WITH CHECK (is_company_member(auth.uid(), company_id));
CREATE INDEX idx_purchases_company ON public.purchases(company_id);

CREATE TABLE public.purchase_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  purchase_id uuid NOT NULL,
  product_id uuid,
  product_name text NOT NULL,
  quantity numeric NOT NULL DEFAULT 1,
  unit_price numeric NOT NULL DEFAULT 0,
  tax_rate numeric NOT NULL DEFAULT 15,
  total numeric NOT NULL DEFAULT 0
);
ALTER TABLE public.purchase_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "members rw purchase_items" ON public.purchase_items FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM purchases p WHERE p.id = purchase_items.purchase_id AND is_company_member(auth.uid(), p.company_id)))
  WITH CHECK (EXISTS (SELECT 1 FROM purchases p WHERE p.id = purchase_items.purchase_id AND is_company_member(auth.uid(), p.company_id)));

-- Expenses
CREATE TABLE public.expense_categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL,
  name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.expense_categories ENABLE ROW LEVEL SECURITY;
CREATE POLICY "members rw expense_categories" ON public.expense_categories FOR ALL TO authenticated
  USING (is_company_member(auth.uid(), company_id))
  WITH CHECK (is_company_member(auth.uid(), company_id));

CREATE TABLE public.expenses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL,
  category_id uuid,
  description text NOT NULL,
  amount numeric NOT NULL DEFAULT 0,
  expense_date date NOT NULL DEFAULT CURRENT_DATE,
  payment_method text NOT NULL DEFAULT 'cash',
  reference text,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.expenses ENABLE ROW LEVEL SECURITY;
CREATE POLICY "members rw expenses" ON public.expenses FOR ALL TO authenticated
  USING (is_company_member(auth.uid(), company_id))
  WITH CHECK (is_company_member(auth.uid(), company_id));
CREATE INDEX idx_expenses_company_date ON public.expenses(company_id, expense_date);

-- Payments (against sales or purchases)
CREATE TYPE payment_direction AS ENUM ('in','out');
CREATE TABLE public.payments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL,
  direction payment_direction NOT NULL,
  sale_id uuid,
  purchase_id uuid,
  customer_id uuid,
  supplier_id uuid,
  amount numeric NOT NULL DEFAULT 0,
  method text NOT NULL DEFAULT 'cash',
  reference text,
  payment_date date NOT NULL DEFAULT CURRENT_DATE,
  notes text,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;
CREATE POLICY "members rw payments" ON public.payments FOR ALL TO authenticated
  USING (is_company_member(auth.uid(), company_id))
  WITH CHECK (is_company_member(auth.uid(), company_id));
CREATE INDEX idx_payments_company_date ON public.payments(company_id, payment_date);

-- Notifications
CREATE TABLE public.notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL,
  user_id uuid,
  title text NOT NULL,
  body text,
  type text NOT NULL DEFAULT 'info',
  link text,
  is_read boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY "members read notifications" ON public.notifications FOR SELECT TO authenticated
  USING (is_company_member(auth.uid(), company_id) AND (user_id IS NULL OR user_id = auth.uid()));
CREATE POLICY "members update notifications" ON public.notifications FOR UPDATE TO authenticated
  USING (is_company_member(auth.uid(), company_id) AND (user_id IS NULL OR user_id = auth.uid()));
CREATE POLICY "members insert notifications" ON public.notifications FOR INSERT TO authenticated
  WITH CHECK (is_company_member(auth.uid(), company_id));

-- Platform admin role (separate from company role)
CREATE TABLE public.platform_admins (
  user_id uuid PRIMARY KEY,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.platform_admins ENABLE ROW LEVEL SECURITY;
CREATE POLICY "self read admin" ON public.platform_admins FOR SELECT TO authenticated USING (user_id = auth.uid());

CREATE OR REPLACE FUNCTION public.is_platform_admin(_user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS(SELECT 1 FROM public.platform_admins WHERE user_id = _user_id);
$$;

-- updated_at triggers
CREATE TRIGGER trg_suppliers_updated BEFORE UPDATE ON public.suppliers FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_purchases_updated BEFORE UPDATE ON public.purchases FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_expenses_updated BEFORE UPDATE ON public.expenses FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
