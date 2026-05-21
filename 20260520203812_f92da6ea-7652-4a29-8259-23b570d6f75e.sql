
-- Cost centers
CREATE TABLE public.cost_centers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL,
  code TEXT NOT NULL,
  name TEXT NOT NULL,
  parent_id UUID,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(company_id, code)
);
ALTER TABLE public.cost_centers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "members read cost_centers" ON public.cost_centers FOR SELECT TO authenticated
  USING (public.is_company_member(auth.uid(), company_id));
CREATE POLICY "owners manage cost_centers" ON public.cost_centers FOR ALL TO authenticated
  USING (public.has_company_role(auth.uid(), company_id, ARRAY['owner'::app_role,'admin'::app_role,'accountant'::app_role]))
  WITH CHECK (public.has_company_role(auth.uid(), company_id, ARRAY['owner'::app_role,'admin'::app_role,'accountant'::app_role]));
CREATE TRIGGER trg_cost_centers_updated BEFORE UPDATE ON public.cost_centers
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Add cost_center to journal_lines & expenses
ALTER TABLE public.journal_lines ADD COLUMN cost_center_id UUID;
ALTER TABLE public.expenses ADD COLUMN cost_center_id UUID;

-- Budgets
CREATE TABLE public.budgets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL,
  name TEXT NOT NULL,
  fiscal_year INT NOT NULL,
  period TEXT NOT NULL DEFAULT 'yearly', -- yearly|monthly|quarterly
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.budgets ENABLE ROW LEVEL SECURITY;
CREATE POLICY "members read budgets" ON public.budgets FOR SELECT TO authenticated
  USING (public.is_company_member(auth.uid(), company_id));
CREATE POLICY "owners manage budgets" ON public.budgets FOR ALL TO authenticated
  USING (public.has_company_role(auth.uid(), company_id, ARRAY['owner'::app_role,'admin'::app_role,'accountant'::app_role]))
  WITH CHECK (public.has_company_role(auth.uid(), company_id, ARRAY['owner'::app_role,'admin'::app_role,'accountant'::app_role]));
CREATE TRIGGER trg_budgets_updated BEFORE UPDATE ON public.budgets
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TABLE public.budget_lines (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  budget_id UUID NOT NULL REFERENCES public.budgets(id) ON DELETE CASCADE,
  account_id UUID NOT NULL,
  cost_center_id UUID,
  month INT, -- 1..12 or null = year total
  amount NUMERIC NOT NULL DEFAULT 0
);
ALTER TABLE public.budget_lines ENABLE ROW LEVEL SECURITY;
CREATE POLICY "members rw budget_lines" ON public.budget_lines FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.budgets b WHERE b.id = budget_lines.budget_id AND public.is_company_member(auth.uid(), b.company_id)))
  WITH CHECK (EXISTS (SELECT 1 FROM public.budgets b WHERE b.id = budget_lines.budget_id AND public.is_company_member(auth.uid(), b.company_id)));

-- Fiscal period locks (month close)
CREATE TABLE public.fiscal_periods (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL,
  year INT NOT NULL,
  month INT NOT NULL,
  status TEXT NOT NULL DEFAULT 'open', -- open|closed
  closed_at TIMESTAMPTZ,
  closed_by UUID,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(company_id, year, month)
);
ALTER TABLE public.fiscal_periods ENABLE ROW LEVEL SECURITY;
CREATE POLICY "members read fiscal_periods" ON public.fiscal_periods FOR SELECT TO authenticated
  USING (public.is_company_member(auth.uid(), company_id));
CREATE POLICY "owners manage fiscal_periods" ON public.fiscal_periods FOR ALL TO authenticated
  USING (public.has_company_role(auth.uid(), company_id, ARRAY['owner'::app_role,'admin'::app_role,'accountant'::app_role]))
  WITH CHECK (public.has_company_role(auth.uid(), company_id, ARRAY['owner'::app_role,'admin'::app_role,'accountant'::app_role]));

-- Prevent posting into closed period
CREATE OR REPLACE FUNCTION public.guard_closed_period()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
DECLARE _closed BOOLEAN;
BEGIN
  SELECT (status = 'closed') INTO _closed FROM public.fiscal_periods
   WHERE company_id = NEW.company_id
     AND year = EXTRACT(YEAR FROM NEW.entry_date)::INT
     AND month = EXTRACT(MONTH FROM NEW.entry_date)::INT;
  IF COALESCE(_closed, false) THEN
    RAISE EXCEPTION 'Fiscal period % - % is closed', EXTRACT(YEAR FROM NEW.entry_date), EXTRACT(MONTH FROM NEW.entry_date);
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER trg_guard_closed_period
BEFORE INSERT ON public.journal_entries
FOR EACH ROW EXECUTE FUNCTION public.guard_closed_period();

-- Close period: posts retained-earnings closing entry (year-end)
CREATE OR REPLACE FUNCTION public.close_fiscal_year(_company_id UUID, _year INT)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _net NUMERIC := 0; _entry UUID; _rev NUMERIC; _exp NUMERIC;
BEGIN
  IF NOT public.has_company_role(auth.uid(), _company_id, ARRAY['owner'::app_role,'admin'::app_role,'accountant'::app_role]) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;

  SELECT COALESCE(SUM(jl.credit - jl.debit),0) INTO _rev
    FROM public.journal_lines jl
    JOIN public.journal_entries je ON je.id = jl.entry_id
    JOIN public.accounts a ON a.id = jl.account_id
   WHERE je.company_id = _company_id
     AND EXTRACT(YEAR FROM je.entry_date) = _year
     AND a.type = 'revenue';

  SELECT COALESCE(SUM(jl.debit - jl.credit),0) INTO _exp
    FROM public.journal_lines jl
    JOIN public.journal_entries je ON je.id = jl.entry_id
    JOIN public.accounts a ON a.id = jl.account_id
   WHERE je.company_id = _company_id
     AND EXTRACT(YEAR FROM je.entry_date) = _year
     AND a.type = 'expense';

  _net := _rev - _exp;

  IF _net = 0 THEN RETURN NULL; END IF;

  -- Move net to retained earnings (3020). If profit: DR Revenue summary / CR RE
  _entry := public.post_journal(
    _company_id,
    MAKE_DATE(_year, 12, 31),
    'قيد إقفال السنة ' || _year,
    'year_close', gen_random_uuid(),
    jsonb_build_array(
      jsonb_build_object('code','4010','debit', GREATEST(_net,0),'credit', 0),
      jsonb_build_object('code','3020','debit', 0,'credit', GREATEST(_net,0)),
      jsonb_build_object('code','3020','debit', GREATEST(-_net,0),'credit', 0),
      jsonb_build_object('code','4010','debit', 0,'credit', GREATEST(-_net,0))
    )
  );
  RETURN _entry;
END $$;
