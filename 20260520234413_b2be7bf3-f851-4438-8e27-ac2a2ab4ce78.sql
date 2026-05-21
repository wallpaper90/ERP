
-- Profit & Loss from journal_lines (single source of truth)
CREATE OR REPLACE FUNCTION public.report_pl_from_ledger(
  _company_id uuid, _from date, _to date
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  _revenue numeric := 0;
  _returns numeric := 0;
  _cogs numeric := 0;
  _expenses numeric := 0;
  _tax numeric := 0;
BEGIN
  IF NOT public.is_company_member(auth.uid(), _company_id) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;

  SELECT
    COALESCE(SUM(CASE WHEN a.code = '4010' THEN jl.credit - jl.debit END), 0),
    COALESCE(SUM(CASE WHEN a.code = '4020' THEN jl.debit - jl.credit END), 0),
    COALESCE(SUM(CASE WHEN a.code = '5010' THEN jl.debit - jl.credit END), 0),
    COALESCE(SUM(CASE WHEN a.code = '5020' THEN jl.debit - jl.credit END), 0),
    COALESCE(SUM(CASE WHEN a.code = '2100' THEN jl.credit - jl.debit END), 0)
  INTO _revenue, _returns, _cogs, _expenses, _tax
  FROM public.journal_lines jl
  JOIN public.journal_entries je ON je.id = jl.entry_id
  JOIN public.accounts a ON a.id = jl.account_id
  WHERE je.company_id = _company_id
    AND je.entry_date BETWEEN _from AND _to
    AND je.is_posted = true;

  RETURN jsonb_build_object(
    'from', _from, 'to', _to,
    'revenue', _revenue,
    'returns', _returns,
    'net_revenue', _revenue - _returns,
    'cogs', _cogs,
    'expenses', _expenses,
    'tax_collected', _tax,
    'gross_profit', (_revenue - _returns) - _cogs,
    'net_profit', (_revenue - _returns) - _cogs - _expenses
  );
END $$;

-- Trial balance from ledger
CREATE OR REPLACE FUNCTION public.report_trial_balance(
  _company_id uuid, _as_of date
) RETURNS TABLE(
  account_id uuid, code text, name text, type text,
  debit numeric, credit numeric, balance numeric
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT public.is_company_member(auth.uid(), _company_id) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;

  RETURN QUERY
  SELECT a.id, a.code, a.name, a.type::text,
    COALESCE(SUM(jl.debit), 0)::numeric AS debit,
    COALESCE(SUM(jl.credit), 0)::numeric AS credit,
    COALESCE(SUM(jl.debit - jl.credit), 0)::numeric AS balance
  FROM public.accounts a
  LEFT JOIN public.journal_lines jl ON jl.account_id = a.id
  LEFT JOIN public.journal_entries je ON je.id = jl.entry_id
    AND je.company_id = _company_id AND je.entry_date <= _as_of AND je.is_posted = true
  WHERE a.company_id = _company_id
  GROUP BY a.id, a.code, a.name, a.type
  ORDER BY a.code;
END $$;

-- Monthly summary from ledger (last 12 months)
CREATE OR REPLACE FUNCTION public.report_monthly_from_ledger(
  _company_id uuid
) RETURNS TABLE(
  month_key text, revenue numeric, expenses numeric, cogs numeric, profit numeric
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE _start date := date_trunc('month', CURRENT_DATE - INTERVAL '11 months')::date;
BEGIN
  IF NOT public.is_company_member(auth.uid(), _company_id) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;

  RETURN QUERY
  WITH months AS (
    SELECT to_char(generate_series(_start, CURRENT_DATE, '1 month'::interval), 'YYYY-MM') AS k
  ),
  agg AS (
    SELECT
      to_char(je.entry_date, 'YYYY-MM') AS k,
      SUM(CASE WHEN a.code = '4010' THEN jl.credit - jl.debit ELSE 0 END) AS revenue,
      SUM(CASE WHEN a.code = '5020' THEN jl.debit - jl.credit ELSE 0 END) AS expenses,
      SUM(CASE WHEN a.code = '5010' THEN jl.debit - jl.credit ELSE 0 END) AS cogs
    FROM public.journal_lines jl
    JOIN public.journal_entries je ON je.id = jl.entry_id
    JOIN public.accounts a ON a.id = jl.account_id
    WHERE je.company_id = _company_id
      AND je.entry_date >= _start
      AND je.is_posted = true
    GROUP BY 1
  )
  SELECT m.k,
    COALESCE(agg.revenue, 0),
    COALESCE(agg.expenses, 0),
    COALESCE(agg.cogs, 0),
    COALESCE(agg.revenue, 0) - COALESCE(agg.cogs, 0) - COALESCE(agg.expenses, 0)
  FROM months m LEFT JOIN agg ON agg.k = m.k
  ORDER BY m.k;
END $$;
