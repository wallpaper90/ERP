
-- ============================================================
-- DOUBLE-ENTRY ACCOUNTING SYSTEM
-- ============================================================

-- Account type enum
DO $$ BEGIN
  CREATE TYPE public.account_type AS ENUM ('asset','liability','equity','revenue','expense');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Chart of accounts
CREATE TABLE IF NOT EXISTS public.accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL,
  code text NOT NULL,
  name text NOT NULL,
  type public.account_type NOT NULL,
  parent_id uuid REFERENCES public.accounts(id) ON DELETE SET NULL,
  is_system boolean NOT NULL DEFAULT false,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (company_id, code)
);
CREATE INDEX IF NOT EXISTS idx_accounts_company ON public.accounts(company_id);
CREATE INDEX IF NOT EXISTS idx_accounts_type ON public.accounts(company_id, type);

ALTER TABLE public.accounts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "members read accounts" ON public.accounts;
CREATE POLICY "members read accounts" ON public.accounts
  FOR SELECT TO authenticated
  USING (public.is_company_member(auth.uid(), company_id));

DROP POLICY IF EXISTS "owners manage accounts" ON public.accounts;
CREATE POLICY "owners manage accounts" ON public.accounts
  FOR ALL TO authenticated
  USING (public.has_company_role(auth.uid(), company_id, ARRAY['owner'::app_role,'admin'::app_role,'accountant'::app_role]))
  WITH CHECK (public.has_company_role(auth.uid(), company_id, ARRAY['owner'::app_role,'admin'::app_role,'accountant'::app_role]));

DROP TRIGGER IF EXISTS trg_accounts_updated_at ON public.accounts;
CREATE TRIGGER trg_accounts_updated_at BEFORE UPDATE ON public.accounts
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Journal entries (header)
CREATE TABLE IF NOT EXISTS public.journal_entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL,
  entry_number text NOT NULL,
  entry_date date NOT NULL DEFAULT CURRENT_DATE,
  description text,
  reference_type text,
  reference_id uuid,
  is_posted boolean NOT NULL DEFAULT true,
  is_manual boolean NOT NULL DEFAULT false,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (company_id, entry_number)
);
CREATE INDEX IF NOT EXISTS idx_je_company_date ON public.journal_entries(company_id, entry_date DESC);
CREATE INDEX IF NOT EXISTS idx_je_ref ON public.journal_entries(company_id, reference_type, reference_id);

ALTER TABLE public.journal_entries ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "members read journal_entries" ON public.journal_entries;
CREATE POLICY "members read journal_entries" ON public.journal_entries
  FOR SELECT TO authenticated
  USING (public.is_company_member(auth.uid(), company_id));

DROP POLICY IF EXISTS "members write journal_entries" ON public.journal_entries;
CREATE POLICY "members write journal_entries" ON public.journal_entries
  FOR ALL TO authenticated
  USING (public.is_company_member(auth.uid(), company_id))
  WITH CHECK (public.is_company_member(auth.uid(), company_id));

-- Journal lines (debit/credit detail)
CREATE TABLE IF NOT EXISTS public.journal_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entry_id uuid NOT NULL REFERENCES public.journal_entries(id) ON DELETE CASCADE,
  account_id uuid NOT NULL REFERENCES public.accounts(id),
  debit numeric NOT NULL DEFAULT 0,
  credit numeric NOT NULL DEFAULT 0,
  description text,
  CHECK (debit >= 0 AND credit >= 0),
  CHECK (NOT (debit > 0 AND credit > 0))
);
CREATE INDEX IF NOT EXISTS idx_jl_entry ON public.journal_lines(entry_id);
CREATE INDEX IF NOT EXISTS idx_jl_account ON public.journal_lines(account_id);

ALTER TABLE public.journal_lines ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "members rw journal_lines" ON public.journal_lines;
CREATE POLICY "members rw journal_lines" ON public.journal_lines
  FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.journal_entries je
                 WHERE je.id = entry_id AND public.is_company_member(auth.uid(), je.company_id)))
  WITH CHECK (EXISTS (SELECT 1 FROM public.journal_entries je
                      WHERE je.id = entry_id AND public.is_company_member(auth.uid(), je.company_id)));

-- ============================================================
-- HELPERS
-- ============================================================

-- Seed default chart of accounts for a company
CREATE OR REPLACE FUNCTION public.seed_company_accounts(_company_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.accounts (company_id, code, name, type, is_system) VALUES
    (_company_id, '1010', 'النقدية', 'asset', true),
    (_company_id, '1020', 'البنك', 'asset', true),
    (_company_id, '1100', 'العملاء (مدينون)', 'asset', true),
    (_company_id, '1200', 'المخزون', 'asset', true),
    (_company_id, '2010', 'الموردون (دائنون)', 'liability', true),
    (_company_id, '2100', 'الضرائب المستحقة', 'liability', true),
    (_company_id, '3010', 'رأس المال', 'equity', true),
    (_company_id, '3020', 'الأرباح المحتجزة', 'equity', true),
    (_company_id, '4010', 'إيرادات المبيعات', 'revenue', true),
    (_company_id, '4020', 'مرتجعات المبيعات', 'revenue', true),
    (_company_id, '5010', 'تكلفة البضاعة المباعة', 'expense', true),
    (_company_id, '5020', 'المصاريف التشغيلية', 'expense', true),
    (_company_id, '5030', 'مرتجعات المشتريات', 'expense', true)
  ON CONFLICT (company_id, code) DO NOTHING;
END $$;

-- Get account id by code (creates if missing - safety net)
CREATE OR REPLACE FUNCTION public.get_account_id(_company_id uuid, _code text)
RETURNS uuid LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE _id uuid;
BEGIN
  SELECT id INTO _id FROM public.accounts
   WHERE company_id = _company_id AND code = _code LIMIT 1;
  RETURN _id;
END $$;

-- Post a journal entry from a JSON list of lines [{code, debit, credit}, ...]
-- Validates balance, generates entry_number, inserts header + lines atomically.
CREATE OR REPLACE FUNCTION public.post_journal(
  _company_id uuid,
  _date date,
  _description text,
  _ref_type text,
  _ref_id uuid,
  _lines jsonb
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  _entry_id uuid;
  _entry_number text;
  _line jsonb;
  _account_id uuid;
  _debit numeric;
  _credit numeric;
  _total_debit numeric := 0;
  _total_credit numeric := 0;
BEGIN
  -- Skip if no company
  IF _company_id IS NULL THEN RETURN NULL; END IF;

  -- Ensure chart of accounts exists
  IF NOT EXISTS (SELECT 1 FROM public.accounts WHERE company_id = _company_id) THEN
    PERFORM public.seed_company_accounts(_company_id);
  END IF;

  -- If a journal already exists for this reference, delete it (idempotent re-post)
  IF _ref_type IS NOT NULL AND _ref_id IS NOT NULL THEN
    DELETE FROM public.journal_entries
     WHERE company_id = _company_id
       AND reference_type = _ref_type
       AND reference_id = _ref_id;
  END IF;

  -- Validate totals
  FOR _line IN SELECT * FROM jsonb_array_elements(_lines) LOOP
    _debit  := COALESCE((_line->>'debit')::numeric, 0);
    _credit := COALESCE((_line->>'credit')::numeric, 0);
    _total_debit  := _total_debit + _debit;
    _total_credit := _total_credit + _credit;
  END LOOP;

  -- Skip empty journals
  IF _total_debit = 0 AND _total_credit = 0 THEN RETURN NULL; END IF;

  -- Tolerance for floating-point rounding (1 millième)
  IF ABS(_total_debit - _total_credit) > 0.01 THEN
    RAISE EXCEPTION 'Unbalanced journal: debit=% credit=% (ref=% %)',
      _total_debit, _total_credit, _ref_type, _ref_id;
  END IF;

  -- Generate entry number JE-YYYYMMDD-NNNN
  SELECT 'JE-' || TO_CHAR(now(),'YYYYMMDD') || '-' ||
         LPAD((COUNT(*)+1)::text, 4, '0')
    INTO _entry_number
    FROM public.journal_entries
   WHERE company_id = _company_id
     AND entry_date = CURRENT_DATE;

  INSERT INTO public.journal_entries (
    company_id, entry_number, entry_date, description, reference_type, reference_id, is_posted, created_by
  ) VALUES (
    _company_id, _entry_number, _date, _description, _ref_type, _ref_id, true,
    NULLIF(current_setting('request.jwt.claim.sub', true),'')::uuid
  ) RETURNING id INTO _entry_id;

  -- Insert lines
  FOR _line IN SELECT * FROM jsonb_array_elements(_lines) LOOP
    _debit  := COALESCE((_line->>'debit')::numeric, 0);
    _credit := COALESCE((_line->>'credit')::numeric, 0);
    IF _debit = 0 AND _credit = 0 THEN CONTINUE; END IF;

    _account_id := public.get_account_id(_company_id, _line->>'code');
    IF _account_id IS NULL THEN
      RAISE EXCEPTION 'Account code % not found for company %', _line->>'code', _company_id;
    END IF;

    INSERT INTO public.journal_lines (entry_id, account_id, debit, credit, description)
    VALUES (_entry_id, _account_id, _debit, _credit, _line->>'description');
  END LOOP;

  RETURN _entry_id;
END $$;

-- ============================================================
-- AUTO-POSTING TRIGGERS
-- ============================================================

-- Sales invoice
CREATE OR REPLACE FUNCTION public.je_on_sale()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _sales numeric;
BEGIN
  IF NEW.deleted_at IS NOT NULL THEN
    DELETE FROM public.journal_entries
     WHERE company_id = NEW.company_id AND reference_type = 'sale' AND reference_id = NEW.id;
    RETURN NEW;
  END IF;

  _sales := COALESCE(NEW.total,0) - COALESCE(NEW.tax_amount,0);

  PERFORM public.post_journal(
    NEW.company_id,
    NEW.invoice_date,
    'فاتورة بيع رقم ' || NEW.invoice_number,
    'sale', NEW.id,
    jsonb_build_array(
      jsonb_build_object('code', CASE WHEN COALESCE(NEW.paid_amount,0) >= COALESCE(NEW.total,0) THEN '1010' ELSE '1100' END,
                         'debit', NEW.total, 'credit', 0),
      jsonb_build_object('code','4010','debit',0,'credit', _sales),
      jsonb_build_object('code','2100','debit',0,'credit', COALESCE(NEW.tax_amount,0))
    )
  );
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_je_sale ON public.sales;
CREATE TRIGGER trg_je_sale AFTER INSERT OR UPDATE ON public.sales
  FOR EACH ROW EXECUTE FUNCTION public.je_on_sale();

-- Purchase invoice
CREATE OR REPLACE FUNCTION public.je_on_purchase()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _net numeric;
BEGIN
  IF NEW.deleted_at IS NOT NULL THEN
    DELETE FROM public.journal_entries
     WHERE company_id = NEW.company_id AND reference_type = 'purchase' AND reference_id = NEW.id;
    RETURN NEW;
  END IF;

  _net := COALESCE(NEW.total,0) - COALESCE(NEW.tax_amount,0);

  PERFORM public.post_journal(
    NEW.company_id,
    NEW.invoice_date,
    'فاتورة شراء رقم ' || NEW.invoice_number,
    'purchase', NEW.id,
    jsonb_build_array(
      jsonb_build_object('code','1200','debit', _net, 'credit', 0),
      jsonb_build_object('code','2100','debit', COALESCE(NEW.tax_amount,0), 'credit', 0),
      jsonb_build_object('code', CASE WHEN COALESCE(NEW.paid_amount,0) >= COALESCE(NEW.total,0) THEN '1010' ELSE '2010' END,
                         'debit', 0, 'credit', NEW.total)
    )
  );
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_je_purchase ON public.purchases;
CREATE TRIGGER trg_je_purchase AFTER INSERT OR UPDATE ON public.purchases
  FOR EACH ROW EXECUTE FUNCTION public.je_on_purchase();

-- Payments
CREATE OR REPLACE FUNCTION public.je_on_payment()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _cash_code text;
BEGIN
  IF NEW.deleted_at IS NOT NULL THEN
    DELETE FROM public.journal_entries
     WHERE company_id = NEW.company_id AND reference_type = 'payment' AND reference_id = NEW.id;
    RETURN NEW;
  END IF;

  _cash_code := CASE
    WHEN NEW.method IN ('bank','transfer','card') THEN '1020'
    ELSE '1010'
  END;

  IF NEW.direction = 'in' THEN
    -- Customer paid us: DR cash/bank, CR AR
    PERFORM public.post_journal(
      NEW.company_id, NEW.payment_date,
      'تحصيل من عميل',
      'payment', NEW.id,
      jsonb_build_array(
        jsonb_build_object('code', _cash_code, 'debit', NEW.amount, 'credit', 0),
        jsonb_build_object('code','1100','debit', 0,'credit', NEW.amount)
      )
    );
  ELSE
    -- We paid supplier: DR AP, CR cash/bank
    PERFORM public.post_journal(
      NEW.company_id, NEW.payment_date,
      'سداد لمورد',
      'payment', NEW.id,
      jsonb_build_array(
        jsonb_build_object('code','2010','debit', NEW.amount, 'credit', 0),
        jsonb_build_object('code', _cash_code,'debit', 0,'credit', NEW.amount)
      )
    );
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_je_payment ON public.payments;
CREATE TRIGGER trg_je_payment AFTER INSERT OR UPDATE ON public.payments
  FOR EACH ROW EXECUTE FUNCTION public.je_on_payment();

-- Expenses
CREATE OR REPLACE FUNCTION public.je_on_expense()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _cash_code text;
BEGIN
  IF NEW.deleted_at IS NOT NULL THEN
    DELETE FROM public.journal_entries
     WHERE company_id = NEW.company_id AND reference_type = 'expense' AND reference_id = NEW.id;
    RETURN NEW;
  END IF;

  _cash_code := CASE
    WHEN NEW.payment_method IN ('bank','transfer','card') THEN '1020'
    ELSE '1010'
  END;

  PERFORM public.post_journal(
    NEW.company_id, NEW.expense_date,
    COALESCE(NEW.description,'مصروف'),
    'expense', NEW.id,
    jsonb_build_array(
      jsonb_build_object('code','5020','debit', NEW.amount,'credit', 0),
      jsonb_build_object('code', _cash_code,'debit', 0,'credit', NEW.amount)
    )
  );
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_je_expense ON public.expenses;
CREATE TRIGGER trg_je_expense AFTER INSERT OR UPDATE ON public.expenses
  FOR EACH ROW EXECUTE FUNCTION public.je_on_expense();

-- Sales returns
CREATE OR REPLACE FUNCTION public.je_on_sales_return()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _cash_code text;
BEGIN
  IF NEW.deleted_at IS NOT NULL THEN
    DELETE FROM public.journal_entries
     WHERE company_id = NEW.company_id AND reference_type = 'sales_return' AND reference_id = NEW.id;
    RETURN NEW;
  END IF;

  _cash_code := CASE
    WHEN NEW.refund_method IN ('bank','transfer','card') THEN '1020'
    WHEN NEW.refund_method = 'credit' THEN '1100'
    ELSE '1010'
  END;

  -- DR Sales Returns (contra-revenue) for refund_amount; CR cash/bank/AR
  IF COALESCE(NEW.refund_amount,0) > 0 THEN
    PERFORM public.post_journal(
      NEW.company_id, NEW.return_date,
      'مرتجع مبيعات ' || NEW.return_number,
      'sales_return', NEW.id,
      jsonb_build_array(
        jsonb_build_object('code','4020','debit', NEW.refund_amount,'credit', 0),
        jsonb_build_object('code', _cash_code,'debit', 0,'credit', NEW.refund_amount)
      )
    );
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_je_sales_return ON public.sales_returns;
CREATE TRIGGER trg_je_sales_return AFTER INSERT OR UPDATE ON public.sales_returns
  FOR EACH ROW EXECUTE FUNCTION public.je_on_sales_return();

-- Purchase returns
CREATE OR REPLACE FUNCTION public.je_on_purchase_return()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.deleted_at IS NOT NULL THEN
    DELETE FROM public.journal_entries
     WHERE company_id = NEW.company_id AND reference_type = 'purchase_return' AND reference_id = NEW.id;
    RETURN NEW;
  END IF;

  IF COALESCE(NEW.total,0) > 0 THEN
    -- DR AP (supplier owes less), CR Inventory / purchase-returns
    PERFORM public.post_journal(
      NEW.company_id, NEW.return_date,
      'مرتجع مشتريات ' || NEW.return_number,
      'purchase_return', NEW.id,
      jsonb_build_array(
        jsonb_build_object('code','2010','debit', NEW.total,'credit', 0),
        jsonb_build_object('code','1200','debit', 0,'credit', NEW.total)
      )
    );
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_je_purchase_return ON public.purchase_returns;
CREATE TRIGGER trg_je_purchase_return AFTER INSERT OR UPDATE ON public.purchase_returns
  FOR EACH ROW EXECUTE FUNCTION public.je_on_purchase_return();

-- POS orders
CREATE OR REPLACE FUNCTION public.je_on_pos_order()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _cash_code text; _sales numeric;
BEGIN
  IF NEW.status = 'voided' THEN
    DELETE FROM public.journal_entries
     WHERE company_id = NEW.company_id AND reference_type = 'pos_order' AND reference_id = NEW.id;
    RETURN NEW;
  END IF;

  _cash_code := CASE WHEN NEW.payment_method IN ('bank','transfer','card') THEN '1020' ELSE '1010' END;
  _sales := COALESCE(NEW.total,0) - COALESCE(NEW.tax_amount,0);

  PERFORM public.post_journal(
    NEW.company_id, NEW.created_at::date,
    'بيع نقطة بيع ' || NEW.order_number,
    'pos_order', NEW.id,
    jsonb_build_array(
      jsonb_build_object('code', _cash_code,'debit', NEW.total,'credit', 0),
      jsonb_build_object('code','4010','debit', 0,'credit', _sales),
      jsonb_build_object('code','2100','debit', 0,'credit', COALESCE(NEW.tax_amount,0))
    )
  );
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_je_pos_order ON public.pos_orders;
CREATE TRIGGER trg_je_pos_order AFTER INSERT OR UPDATE ON public.pos_orders
  FOR EACH ROW EXECUTE FUNCTION public.je_on_pos_order();

-- ============================================================
-- SEED + BACKFILL EXISTING DATA
-- ============================================================

DO $$
DECLARE _c uuid;
BEGIN
  -- Seed chart of accounts for every existing company
  FOR _c IN SELECT id FROM public.companies WHERE deleted_at IS NULL LOOP
    PERFORM public.seed_company_accounts(_c);
  END LOOP;
END $$;

-- Backfill journals for existing rows (idempotent: post_journal deletes prior entries for the same ref)
-- Sales
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM public.sales WHERE deleted_at IS NULL LOOP
    PERFORM public.post_journal(
      r.company_id, r.invoice_date,
      'فاتورة بيع رقم ' || r.invoice_number,
      'sale', r.id,
      jsonb_build_array(
        jsonb_build_object('code', CASE WHEN COALESCE(r.paid_amount,0) >= COALESCE(r.total,0) THEN '1010' ELSE '1100' END,
                           'debit', r.total, 'credit', 0),
        jsonb_build_object('code','4010','debit', 0,'credit', COALESCE(r.total,0) - COALESCE(r.tax_amount,0)),
        jsonb_build_object('code','2100','debit', 0,'credit', COALESCE(r.tax_amount,0))
      )
    );
  END LOOP;
END $$;

-- Purchases
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM public.purchases WHERE deleted_at IS NULL LOOP
    PERFORM public.post_journal(
      r.company_id, r.invoice_date,
      'فاتورة شراء رقم ' || r.invoice_number,
      'purchase', r.id,
      jsonb_build_array(
        jsonb_build_object('code','1200','debit', COALESCE(r.total,0) - COALESCE(r.tax_amount,0), 'credit', 0),
        jsonb_build_object('code','2100','debit', COALESCE(r.tax_amount,0), 'credit', 0),
        jsonb_build_object('code', CASE WHEN COALESCE(r.paid_amount,0) >= COALESCE(r.total,0) THEN '1010' ELSE '2010' END,
                           'debit', 0, 'credit', r.total)
      )
    );
  END LOOP;
END $$;

-- Payments
DO $$
DECLARE r record; _cash text;
BEGIN
  FOR r IN SELECT * FROM public.payments WHERE deleted_at IS NULL LOOP
    _cash := CASE WHEN r.method IN ('bank','transfer','card') THEN '1020' ELSE '1010' END;
    IF r.direction = 'in' THEN
      PERFORM public.post_journal(r.company_id, r.payment_date, 'تحصيل من عميل', 'payment', r.id,
        jsonb_build_array(
          jsonb_build_object('code', _cash, 'debit', r.amount, 'credit', 0),
          jsonb_build_object('code','1100','debit', 0,'credit', r.amount)
        ));
    ELSE
      PERFORM public.post_journal(r.company_id, r.payment_date, 'سداد لمورد', 'payment', r.id,
        jsonb_build_array(
          jsonb_build_object('code','2010','debit', r.amount, 'credit', 0),
          jsonb_build_object('code', _cash,'debit', 0,'credit', r.amount)
        ));
    END IF;
  END LOOP;
END $$;

-- Expenses
DO $$
DECLARE r record; _cash text;
BEGIN
  FOR r IN SELECT * FROM public.expenses WHERE deleted_at IS NULL LOOP
    _cash := CASE WHEN r.payment_method IN ('bank','transfer','card') THEN '1020' ELSE '1010' END;
    PERFORM public.post_journal(r.company_id, r.expense_date, COALESCE(r.description,'مصروف'), 'expense', r.id,
      jsonb_build_array(
        jsonb_build_object('code','5020','debit', r.amount,'credit', 0),
        jsonb_build_object('code', _cash,'debit', 0,'credit', r.amount)
      ));
  END LOOP;
END $$;

-- POS orders
DO $$
DECLARE r record; _cash text;
BEGIN
  FOR r IN SELECT * FROM public.pos_orders WHERE status != 'voided' LOOP
    _cash := CASE WHEN r.payment_method IN ('bank','transfer','card') THEN '1020' ELSE '1010' END;
    PERFORM public.post_journal(r.company_id, r.created_at::date, 'بيع نقطة بيع ' || r.order_number, 'pos_order', r.id,
      jsonb_build_array(
        jsonb_build_object('code', _cash,'debit', r.total,'credit', 0),
        jsonb_build_object('code','4010','debit', 0,'credit', COALESCE(r.total,0) - COALESCE(r.tax_amount,0)),
        jsonb_build_object('code','2100','debit', 0,'credit', COALESCE(r.tax_amount,0))
      ));
  END LOOP;
END $$;
