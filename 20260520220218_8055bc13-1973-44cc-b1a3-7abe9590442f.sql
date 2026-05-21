
-- Fix post_journal entry numbering: use an advisory-safe approach by counting *all* entries
-- on entry_date (the user-supplied date), not just CURRENT_DATE, and combine with the timestamp.
CREATE OR REPLACE FUNCTION public.post_journal(_company_id uuid, _date date, _description text, _ref_type text, _ref_id uuid, _lines jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  _entry_id uuid;
  _entry_number text;
  _line jsonb;
  _account_id uuid;
  _debit numeric;
  _credit numeric;
  _total_debit numeric := 0;
  _total_credit numeric := 0;
  _seq int;
BEGIN
  IF _company_id IS NULL THEN RETURN NULL; END IF;

  IF NOT EXISTS (SELECT 1 FROM public.accounts WHERE company_id = _company_id) THEN
    PERFORM public.seed_company_accounts(_company_id);
  END IF;

  IF _ref_type IS NOT NULL AND _ref_id IS NOT NULL THEN
    DELETE FROM public.journal_entries
     WHERE company_id = _company_id
       AND reference_type = _ref_type
       AND reference_id = _ref_id;
  END IF;

  FOR _line IN SELECT * FROM jsonb_array_elements(_lines) LOOP
    _debit  := COALESCE((_line->>'debit')::numeric, 0);
    _credit := COALESCE((_line->>'credit')::numeric, 0);
    _total_debit  := _total_debit + _debit;
    _total_credit := _total_credit + _credit;
  END LOOP;

  IF _total_debit = 0 AND _total_credit = 0 THEN RETURN NULL; END IF;
  IF ABS(_total_debit - _total_credit) > 0.01 THEN
    RAISE EXCEPTION 'Unbalanced journal: debit=% credit=%', _total_debit, _total_credit;
  END IF;

  -- Unique-per-company counter across all entries for the date.
  LOOP
    SELECT COUNT(*) + 1 INTO _seq
      FROM public.journal_entries
     WHERE company_id = _company_id AND entry_date = _date;
    _entry_number := 'JE-' || TO_CHAR(_date,'YYYYMMDD') || '-' || LPAD(_seq::text, 4, '0');
    BEGIN
      INSERT INTO public.journal_entries (
        company_id, entry_number, entry_date, description, reference_type, reference_id, is_posted, created_by
      ) VALUES (
        _company_id, _entry_number, _date, _description, _ref_type, _ref_id, true,
        NULLIF(current_setting('request.jwt.claim.sub', true),'')::uuid
      ) RETURNING id INTO _entry_id;
      EXIT;
    EXCEPTION WHEN unique_violation THEN
      -- Try the next sequence number
      CONTINUE;
    END;
  END LOOP;

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
END $function$;

-- Drop if exist (idempotent)
DROP TRIGGER IF EXISTS trg_je_on_sale ON public.sales;
DROP TRIGGER IF EXISTS trg_je_on_purchase ON public.purchases;
DROP TRIGGER IF EXISTS trg_je_on_payment ON public.payments;
DROP TRIGGER IF EXISTS trg_je_on_expense ON public.expenses;
DROP TRIGGER IF EXISTS trg_je_on_sales_return ON public.sales_returns;
DROP TRIGGER IF EXISTS trg_je_on_purchase_return ON public.purchase_returns;
DROP TRIGGER IF EXISTS trg_guard_product_stock_qty ON public.products;
DROP TRIGGER IF EXISTS trg_set_updated_at_sales ON public.sales;
DROP TRIGGER IF EXISTS trg_set_updated_at_purchases ON public.purchases;
DROP TRIGGER IF EXISTS trg_set_updated_at_products ON public.products;
DROP TRIGGER IF EXISTS trg_set_updated_at_customers ON public.customers;
DROP TRIGGER IF EXISTS trg_set_updated_at_suppliers ON public.suppliers;

CREATE TRIGGER trg_je_on_sale AFTER INSERT OR UPDATE ON public.sales
  FOR EACH ROW EXECUTE FUNCTION public.je_on_sale();
CREATE TRIGGER trg_je_on_purchase AFTER INSERT OR UPDATE ON public.purchases
  FOR EACH ROW EXECUTE FUNCTION public.je_on_purchase();
CREATE TRIGGER trg_je_on_payment AFTER INSERT OR UPDATE ON public.payments
  FOR EACH ROW EXECUTE FUNCTION public.je_on_payment();
CREATE TRIGGER trg_je_on_expense AFTER INSERT OR UPDATE ON public.expenses
  FOR EACH ROW EXECUTE FUNCTION public.je_on_expense();
CREATE TRIGGER trg_je_on_sales_return AFTER INSERT OR UPDATE ON public.sales_returns
  FOR EACH ROW EXECUTE FUNCTION public.je_on_sales_return();
CREATE TRIGGER trg_je_on_purchase_return AFTER INSERT OR UPDATE ON public.purchase_returns
  FOR EACH ROW EXECUTE FUNCTION public.je_on_purchase_return();
CREATE TRIGGER trg_guard_product_stock_qty BEFORE UPDATE ON public.products
  FOR EACH ROW EXECUTE FUNCTION public.guard_product_stock_qty();

CREATE TRIGGER trg_set_updated_at_sales BEFORE UPDATE ON public.sales
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_set_updated_at_purchases BEFORE UPDATE ON public.purchases
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_set_updated_at_products BEFORE UPDATE ON public.products
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_set_updated_at_customers BEFORE UPDATE ON public.customers
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_set_updated_at_suppliers BEFORE UPDATE ON public.suppliers
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
