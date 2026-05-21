CREATE OR REPLACE FUNCTION public.post_journal(
  _company_id uuid,
  _date date,
  _description text,
  _ref_type text,
  _ref_id uuid,
  _lines jsonb
) RETURNS uuid
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
  _effective_date date := COALESCE(_date, CURRENT_DATE);
BEGIN
  IF _company_id IS NULL THEN
    RETURN NULL;
  END IF;

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
    _debit := COALESCE((_line->>'debit')::numeric, 0);
    _credit := COALESCE((_line->>'credit')::numeric, 0);
    _total_debit := _total_debit + _debit;
    _total_credit := _total_credit + _credit;
  END LOOP;

  IF _total_debit = 0 AND _total_credit = 0 THEN
    RETURN NULL;
  END IF;

  IF ABS(_total_debit - _total_credit) > 0.01 THEN
    RAISE EXCEPTION 'Unbalanced journal: debit=% credit=%', _total_debit, _total_credit;
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(_company_id::text || '|' || _effective_date::text, 0));

  SELECT COALESCE(
           MAX(
             COALESCE(
               NULLIF(substring(entry_number from '([0-9]+)$'), ''),
               '0'
             )::int
           ),
           0
         ) + 1
    INTO _seq
    FROM public.journal_entries
   WHERE company_id = _company_id
     AND entry_date = _effective_date
     AND entry_number LIKE 'JE-' || TO_CHAR(_effective_date, 'YYYYMMDD') || '-%';

  _entry_number := 'JE-' || TO_CHAR(_effective_date, 'YYYYMMDD') || '-' || LPAD(_seq::text, 4, '0');

  INSERT INTO public.journal_entries (
    company_id,
    entry_number,
    entry_date,
    description,
    reference_type,
    reference_id,
    is_posted,
    created_by
  ) VALUES (
    _company_id,
    _entry_number,
    _effective_date,
    _description,
    _ref_type,
    _ref_id,
    true,
    NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid
  ) RETURNING id INTO _entry_id;

  FOR _line IN SELECT * FROM jsonb_array_elements(_lines) LOOP
    _debit := COALESCE((_line->>'debit')::numeric, 0);
    _credit := COALESCE((_line->>'credit')::numeric, 0);

    IF _debit = 0 AND _credit = 0 THEN
      CONTINUE;
    END IF;

    _account_id := public.get_account_id(_company_id, _line->>'code');
    IF _account_id IS NULL THEN
      RAISE EXCEPTION 'Account code % not found for company %', _line->>'code', _company_id;
    END IF;

    INSERT INTO public.journal_lines (entry_id, account_id, debit, credit, description)
    VALUES (_entry_id, _account_id, _debit, _credit, _line->>'description');
  END LOOP;

  RETURN _entry_id;
END
$function$;

DROP TRIGGER IF EXISTS trg_sales_updated ON public.sales;
DROP TRIGGER IF EXISTS trg_purchases_updated ON public.purchases;