-- 1) profiles: store user's active company + pending company name from signup
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS active_company_id uuid,
  ADD COLUMN IF NOT EXISTS pending_company_name text;

-- 2) handle_new_user: also capture pending_company_name from signup metadata
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  INSERT INTO public.profiles (id, email, full_name, pending_company_name)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email),
    NULLIF(NEW.raw_user_meta_data->>'company_name', '')
  );
  RETURN NEW;
END;
$function$;

-- 3) set_active_company — switch user's active company (must be a member)
CREATE OR REPLACE FUNCTION public.set_active_company(_company_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF NOT public.is_company_member(auth.uid(), _company_id) THEN
    RAISE EXCEPTION 'Not a member of this company';
  END IF;
  UPDATE public.profiles SET active_company_id = _company_id WHERE id = auth.uid();
END $$;

-- 4) reset_company_data — wipe all transactional data for a company (owner/admin only)
CREATE OR REPLACE FUNCTION public.reset_company_data(_company_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF NOT public.has_company_role(auth.uid(), _company_id, ARRAY['owner'::app_role,'admin'::app_role]) THEN
    RAISE EXCEPTION 'Only owners and admins can reset company data';
  END IF;

  DELETE FROM public.journal_lines  WHERE entry_id IN (SELECT id FROM public.journal_entries WHERE company_id = _company_id);
  DELETE FROM public.journal_entries WHERE company_id = _company_id;

  DELETE FROM public.sales_return_items   WHERE return_id IN (SELECT id FROM public.sales_returns   WHERE company_id = _company_id);
  DELETE FROM public.sales_returns        WHERE company_id = _company_id;
  DELETE FROM public.purchase_return_items WHERE return_id IN (SELECT id FROM public.purchase_returns WHERE company_id = _company_id);
  DELETE FROM public.purchase_returns     WHERE company_id = _company_id;

  DELETE FROM public.payments         WHERE company_id = _company_id;
  DELETE FROM public.pos_order_items  WHERE order_id IN (SELECT id FROM public.pos_orders WHERE company_id = _company_id);
  DELETE FROM public.pos_orders       WHERE company_id = _company_id;
  DELETE FROM public.pos_sessions     WHERE company_id = _company_id;

  DELETE FROM public.sale_items       WHERE sale_id IN (SELECT id FROM public.sales WHERE company_id = _company_id);
  DELETE FROM public.sales            WHERE company_id = _company_id;
  DELETE FROM public.purchase_items   WHERE purchase_id IN (SELECT id FROM public.purchases WHERE company_id = _company_id);
  DELETE FROM public.purchases        WHERE company_id = _company_id;

  DELETE FROM public.expenses         WHERE company_id = _company_id;
  DELETE FROM public.stock_movements  WHERE company_id = _company_id;
  DELETE FROM public.domain_events    WHERE company_id = _company_id;
  DELETE FROM public.audit_logs       WHERE company_id = _company_id;
  DELETE FROM public.notifications    WHERE company_id = _company_id;

  -- reset stock counts
  PERFORM set_config('app.allow_stock_update', 'true', true);
  UPDATE public.products SET stock_qty = 0 WHERE company_id = _company_id;

  -- reset balances
  UPDATE public.customers SET balance = 0 WHERE company_id = _company_id;
  UPDATE public.suppliers SET balance = 0 WHERE company_id = _company_id;
END $$;

-- 5) self_register_company — let a newly signed-up user create their own company shell.
--    No company_members row is inserted, so they remain "pending approval"
--    until a platform admin assigns them a role.
CREATE OR REPLACE FUNCTION public.self_register_company(_company_name text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE _company_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Must be authenticated'; END IF;
  IF _company_name IS NULL OR length(trim(_company_name)) = 0 THEN
    RAISE EXCEPTION 'Company name required';
  END IF;

  INSERT INTO public.companies(name, created_by)
  VALUES (trim(_company_name), auth.uid())
  RETURNING id INTO _company_id;

  INSERT INTO public.subscriptions(company_id, plan, status)
  VALUES (_company_id, 'trial', 'active')
  ON CONFLICT (company_id) DO NOTHING;

  UPDATE public.profiles
    SET pending_company_name = trim(_company_name)
    WHERE id = auth.uid();

  RETURN _company_id;
END $$;