
-- Enums
CREATE TYPE public.app_role AS ENUM ('owner', 'admin', 'user');
CREATE TYPE public.subscription_plan AS ENUM ('trial', 'basic', 'pro');
CREATE TYPE public.subscription_status AS ENUM ('active', 'cancelled', 'expired');
CREATE TYPE public.sale_status AS ENUM ('draft', 'confirmed', 'paid', 'cancelled');

-- Companies (tenants)
CREATE TABLE public.companies (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  currency TEXT NOT NULL DEFAULT 'SAR',
  tax_number TEXT,
  phone TEXT,
  address TEXT,
  created_by UUID NOT NULL REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Profiles
CREATE TABLE public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name TEXT,
  email TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Company members (membership + role)
CREATE TABLE public.company_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role public.app_role NOT NULL DEFAULT 'user',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(company_id, user_id)
);

-- Subscriptions
CREATE TABLE public.subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL UNIQUE REFERENCES public.companies(id) ON DELETE CASCADE,
  plan public.subscription_plan NOT NULL DEFAULT 'trial',
  status public.subscription_status NOT NULL DEFAULT 'active',
  trial_ends_at TIMESTAMPTZ DEFAULT (now() + interval '14 days'),
  current_period_end TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Customers
CREATE TABLE public.customers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  phone TEXT,
  email TEXT,
  address TEXT,
  tax_number TEXT,
  balance NUMERIC(14,2) NOT NULL DEFAULT 0,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_customers_company ON public.customers(company_id);

-- Products / Inventory
CREATE TABLE public.products (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  sku TEXT,
  name TEXT NOT NULL,
  description TEXT,
  unit TEXT NOT NULL DEFAULT 'قطعة',
  cost_price NUMERIC(14,2) NOT NULL DEFAULT 0,
  sale_price NUMERIC(14,2) NOT NULL DEFAULT 0,
  stock_qty NUMERIC(14,3) NOT NULL DEFAULT 0,
  min_stock NUMERIC(14,3) NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_products_company ON public.products(company_id);

-- Sales (invoices)
CREATE TABLE public.sales (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  customer_id UUID REFERENCES public.customers(id) ON DELETE SET NULL,
  invoice_number TEXT NOT NULL,
  invoice_date DATE NOT NULL DEFAULT CURRENT_DATE,
  subtotal NUMERIC(14,2) NOT NULL DEFAULT 0,
  tax_amount NUMERIC(14,2) NOT NULL DEFAULT 0,
  discount NUMERIC(14,2) NOT NULL DEFAULT 0,
  total NUMERIC(14,2) NOT NULL DEFAULT 0,
  paid_amount NUMERIC(14,2) NOT NULL DEFAULT 0,
  status public.sale_status NOT NULL DEFAULT 'draft',
  notes TEXT,
  created_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(company_id, invoice_number)
);
CREATE INDEX idx_sales_company ON public.sales(company_id);
CREATE INDEX idx_sales_customer ON public.sales(customer_id);

-- Sale items
CREATE TABLE public.sale_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sale_id UUID NOT NULL REFERENCES public.sales(id) ON DELETE CASCADE,
  product_id UUID REFERENCES public.products(id) ON DELETE SET NULL,
  product_name TEXT NOT NULL,
  quantity NUMERIC(14,3) NOT NULL DEFAULT 1,
  unit_price NUMERIC(14,2) NOT NULL DEFAULT 0,
  tax_rate NUMERIC(5,2) NOT NULL DEFAULT 15,
  total NUMERIC(14,2) NOT NULL DEFAULT 0
);
CREATE INDEX idx_sale_items_sale ON public.sale_items(sale_id);

-- Security definer helpers (avoid recursive RLS)
CREATE OR REPLACE FUNCTION public.get_user_company_ids(_user_id UUID)
RETURNS SETOF UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT company_id FROM public.company_members WHERE user_id = _user_id;
$$;

CREATE OR REPLACE FUNCTION public.is_company_member(_user_id UUID, _company_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS(SELECT 1 FROM public.company_members WHERE user_id = _user_id AND company_id = _company_id);
$$;

CREATE OR REPLACE FUNCTION public.has_company_role(_user_id UUID, _company_id UUID, _roles app_role[])
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS(
    SELECT 1 FROM public.company_members
    WHERE user_id = _user_id AND company_id = _company_id AND role = ANY(_roles)
  );
$$;

-- Auto-create profile on signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, email, full_name)
  VALUES (NEW.id, NEW.email, COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email));
  RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- updated_at triggers
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;

CREATE TRIGGER trg_companies_updated BEFORE UPDATE ON public.companies FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_customers_updated BEFORE UPDATE ON public.customers FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_products_updated BEFORE UPDATE ON public.products FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_sales_updated BEFORE UPDATE ON public.sales FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Enable RLS
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sale_items ENABLE ROW LEVEL SECURITY;

-- Profiles: user can see/edit own
CREATE POLICY "own profile read" ON public.profiles FOR SELECT TO authenticated USING (id = auth.uid());
CREATE POLICY "own profile update" ON public.profiles FOR UPDATE TO authenticated USING (id = auth.uid());

-- Companies: members can read; only creator can insert; owners/admins can update
CREATE POLICY "members read company" ON public.companies FOR SELECT TO authenticated
  USING (public.is_company_member(auth.uid(), id));
CREATE POLICY "users create company" ON public.companies FOR INSERT TO authenticated
  WITH CHECK (created_by = auth.uid());
CREATE POLICY "owners update company" ON public.companies FOR UPDATE TO authenticated
  USING (public.has_company_role(auth.uid(), id, ARRAY['owner','admin']::app_role[]));

-- Company members: members can read; owners/admins manage
CREATE POLICY "members read members" ON public.company_members FOR SELECT TO authenticated
  USING (public.is_company_member(auth.uid(), company_id));
CREATE POLICY "self-insert as owner on new company" ON public.company_members FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid() OR public.has_company_role(auth.uid(), company_id, ARRAY['owner','admin']::app_role[]));
CREATE POLICY "owners manage members" ON public.company_members FOR UPDATE TO authenticated
  USING (public.has_company_role(auth.uid(), company_id, ARRAY['owner','admin']::app_role[]));
CREATE POLICY "owners delete members" ON public.company_members FOR DELETE TO authenticated
  USING (public.has_company_role(auth.uid(), company_id, ARRAY['owner','admin']::app_role[]));

-- Subscriptions: members read; owners manage
CREATE POLICY "members read subscription" ON public.subscriptions FOR SELECT TO authenticated
  USING (public.is_company_member(auth.uid(), company_id));
CREATE POLICY "insert subscription on company create" ON public.subscriptions FOR INSERT TO authenticated
  WITH CHECK (public.is_company_member(auth.uid(), company_id));
CREATE POLICY "owners update subscription" ON public.subscriptions FOR UPDATE TO authenticated
  USING (public.has_company_role(auth.uid(), company_id, ARRAY['owner']::app_role[]));

-- Generic tenant policies: customers, products, sales
CREATE POLICY "members rw customers" ON public.customers FOR ALL TO authenticated
  USING (public.is_company_member(auth.uid(), company_id))
  WITH CHECK (public.is_company_member(auth.uid(), company_id));

CREATE POLICY "members rw products" ON public.products FOR ALL TO authenticated
  USING (public.is_company_member(auth.uid(), company_id))
  WITH CHECK (public.is_company_member(auth.uid(), company_id));

CREATE POLICY "members rw sales" ON public.sales FOR ALL TO authenticated
  USING (public.is_company_member(auth.uid(), company_id))
  WITH CHECK (public.is_company_member(auth.uid(), company_id));

CREATE POLICY "members rw sale_items" ON public.sale_items FOR ALL TO authenticated
  USING (EXISTS(SELECT 1 FROM public.sales s WHERE s.id = sale_id AND public.is_company_member(auth.uid(), s.company_id)))
  WITH CHECK (EXISTS(SELECT 1 FROM public.sales s WHERE s.id = sale_id AND public.is_company_member(auth.uid(), s.company_id)));
