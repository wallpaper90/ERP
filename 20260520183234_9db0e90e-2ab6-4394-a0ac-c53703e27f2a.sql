
-- ============ Extend companies ============
ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS industry TEXT,
  ADD COLUMN IF NOT EXISTS plan TEXT NOT NULL DEFAULT 'trial',
  ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

-- ============ Soft delete on core tables ============
ALTER TABLE public.customers       ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;
ALTER TABLE public.suppliers       ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;
ALTER TABLE public.products        ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;
ALTER TABLE public.sales           ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;
ALTER TABLE public.purchases       ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;
ALTER TABLE public.expenses        ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;
ALTER TABLE public.payments        ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

-- ============ stock_movements ============
DO $$ BEGIN
  CREATE TYPE public.stock_movement_type AS ENUM ('in','out','adjustment','sale','purchase','return');
EXCEPTION WHEN duplicate_object THEN null; END $$;

CREATE TABLE IF NOT EXISTS public.stock_movements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL,
  product_id UUID NOT NULL,
  type public.stock_movement_type NOT NULL,
  quantity NUMERIC NOT NULL,
  reason TEXT,
  reference_type TEXT,
  reference_id UUID,
  created_by UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_stock_movements_company  ON public.stock_movements(company_id);
CREATE INDEX IF NOT EXISTS idx_stock_movements_product  ON public.stock_movements(product_id);
CREATE INDEX IF NOT EXISTS idx_stock_movements_created  ON public.stock_movements(created_at DESC);

ALTER TABLE public.stock_movements ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "members rw stock_movements" ON public.stock_movements;
CREATE POLICY "members rw stock_movements" ON public.stock_movements
  FOR ALL TO authenticated
  USING (public.is_company_member(auth.uid(), company_id) AND deleted_at IS NULL)
  WITH CHECK (public.is_company_member(auth.uid(), company_id));

-- ============ audit_logs ============
CREATE TABLE IF NOT EXISTS public.audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL,
  user_id UUID,
  action TEXT NOT NULL,                 -- create|update|delete|login|...
  entity_type TEXT NOT NULL,            -- customers|invoices|...
  entity_id UUID,
  old_data JSONB,
  new_data JSONB,
  ip_address INET,
  user_agent TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_audit_company  ON public.audit_logs(company_id);
CREATE INDEX IF NOT EXISTS idx_audit_entity   ON public.audit_logs(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_audit_created  ON public.audit_logs(created_at DESC);

ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "members read audit_logs" ON public.audit_logs;
CREATE POLICY "members read audit_logs" ON public.audit_logs
  FOR SELECT TO authenticated
  USING (public.is_company_member(auth.uid(), company_id));

DROP POLICY IF EXISTS "members insert audit_logs" ON public.audit_logs;
CREATE POLICY "members insert audit_logs" ON public.audit_logs
  FOR INSERT TO authenticated
  WITH CHECK (public.is_company_member(auth.uid(), company_id));

-- ============ Helper: log_audit ============
CREATE OR REPLACE FUNCTION public.log_audit(
  _company_id UUID,
  _action TEXT,
  _entity_type TEXT,
  _entity_id UUID,
  _old JSONB DEFAULT NULL,
  _new JSONB DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.audit_logs(company_id, user_id, action, entity_type, entity_id, old_data, new_data)
  VALUES (_company_id, auth.uid(), _action, _entity_type, _entity_id, _old, _new);
END; $$;

-- ============ Helper: record stock movement + update product stock ============
CREATE OR REPLACE FUNCTION public.record_stock_movement(
  _company_id UUID,
  _product_id UUID,
  _type public.stock_movement_type,
  _quantity NUMERIC,
  _reason TEXT DEFAULT NULL,
  _ref_type TEXT DEFAULT NULL,
  _ref_id UUID DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _id UUID; _delta NUMERIC;
BEGIN
  IF NOT public.is_company_member(auth.uid(), _company_id) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;

  _delta := CASE WHEN _type IN ('in','purchase','return','adjustment') THEN _quantity ELSE -_quantity END;

  INSERT INTO public.stock_movements(company_id, product_id, type, quantity, reason, reference_type, reference_id, created_by)
  VALUES (_company_id, _product_id, _type, _quantity, _reason, _ref_type, _ref_id, auth.uid())
  RETURNING id INTO _id;

  UPDATE public.products SET stock_qty = stock_qty + _delta, updated_at = now()
  WHERE id = _product_id AND company_id = _company_id;

  RETURN _id;
END; $$;
