-- 1) Fix sales return: decrease customer balance by full return total (not just refund amount)
CREATE OR REPLACE FUNCTION public.create_sales_return(_company_id uuid, _sale_id uuid, _reason text, _refund_amount numeric, _refund_method text, _restock boolean, _notes text, _items jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  _return_id UUID;
  _return_number TEXT;
  _customer_id UUID;
  _item JSONB;
  _qty NUMERIC;
  _sold_qty NUMERIC;
  _returned_qty NUMERIC;
  _total NUMERIC := 0;
  _line_total NUMERIC;
BEGIN
  IF NOT public.is_company_member(auth.uid(), _company_id) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;

  SELECT customer_id INTO _customer_id FROM public.sales
    WHERE id = _sale_id AND company_id = _company_id AND deleted_at IS NULL;
  IF NOT FOUND THEN RAISE EXCEPTION 'Sale not found'; END IF;

  FOR _item IN SELECT * FROM jsonb_array_elements(_items) LOOP
    _qty := (_item->>'quantity')::NUMERIC;
    IF _qty <= 0 THEN CONTINUE; END IF;
    IF (_item->>'product_id') IS NOT NULL THEN
      SELECT COALESCE(SUM(quantity), 0) INTO _sold_qty
        FROM public.sale_items
        WHERE sale_id = _sale_id AND product_id = (_item->>'product_id')::UUID;
      SELECT COALESCE(SUM(sri.quantity), 0) INTO _returned_qty
        FROM public.sales_return_items sri
        JOIN public.sales_returns sr ON sr.id = sri.return_id
        WHERE sr.sale_id = _sale_id AND sr.deleted_at IS NULL
          AND sri.product_id = (_item->>'product_id')::UUID;
      IF _qty + _returned_qty > _sold_qty THEN
        RAISE EXCEPTION 'Return quantity exceeds sold quantity for product %', _item->>'product_name';
      END IF;
    END IF;
  END LOOP;

  SELECT 'SR-' || TO_CHAR(now(), 'YYYYMMDD') || '-' || LPAD((COUNT(*) + 1)::TEXT, 4, '0')
    INTO _return_number
    FROM public.sales_returns
    WHERE company_id = _company_id AND return_date = CURRENT_DATE;

  INSERT INTO public.sales_returns(
    company_id, sale_id, customer_id, return_number, reason,
    refund_amount, refund_method, restock, notes, created_by
  ) VALUES (
    _company_id, _sale_id, _customer_id, _return_number, _reason,
    COALESCE(_refund_amount, 0), COALESCE(_refund_method, 'cash'),
    COALESCE(_restock, true), _notes, auth.uid()
  ) RETURNING id INTO _return_id;

  FOR _item IN SELECT * FROM jsonb_array_elements(_items) LOOP
    _qty := (_item->>'quantity')::NUMERIC;
    IF _qty <= 0 THEN CONTINUE; END IF;
    _line_total := _qty * COALESCE((_item->>'unit_price')::NUMERIC, 0);
    _total := _total + _line_total;

    INSERT INTO public.sales_return_items(
      return_id, product_id, product_name, quantity, unit_price, total
    ) VALUES (
      _return_id,
      NULLIF(_item->>'product_id','')::UUID,
      _item->>'product_name',
      _qty,
      COALESCE((_item->>'unit_price')::NUMERIC, 0),
      _line_total
    );

    IF COALESCE(_restock, true) AND (_item->>'product_id') IS NOT NULL THEN
      PERFORM public.record_stock_movement(
        _company_id, (_item->>'product_id')::UUID, 'return'::stock_movement_type,
        _qty, 'Sales return', 'sales_return', _return_id
      );
    END IF;
  END LOOP;

  -- FIX: decrease customer balance by the full return total (they owe us less for the returned items).
  -- The refund payment (if any) is recorded separately as a payment row.
  IF _customer_id IS NOT NULL AND _total > 0 THEN
    UPDATE public.customers SET balance = balance - _total, updated_at = now()
      WHERE id = _customer_id AND company_id = _company_id;
  END IF;

  RETURN _return_id;
END;
$function$;

-- 2) Add subscription expiry control: function for platform admin to set company expiry
CREATE OR REPLACE FUNCTION public.set_company_subscription(
  _company_id uuid,
  _plan subscription_plan,
  _status subscription_status,
  _period_end timestamptz
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_platform_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Only platform admins can change subscriptions';
  END IF;

  INSERT INTO public.subscriptions(company_id, plan, status, current_period_end, trial_ends_at)
  VALUES (_company_id, _plan, _status, _period_end, _period_end)
  ON CONFLICT (company_id) DO UPDATE
    SET plan = EXCLUDED.plan,
        status = EXCLUDED.status,
        current_period_end = EXCLUDED.current_period_end,
        trial_ends_at = EXCLUDED.trial_ends_at;

  UPDATE public.companies SET is_active = (_status = 'active'::subscription_status), updated_at = now()
    WHERE id = _company_id;
END $$;

-- Ensure subscriptions has unique constraint on company_id (idempotent)
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'subscriptions_company_id_key'
  ) THEN
    ALTER TABLE public.subscriptions ADD CONSTRAINT subscriptions_company_id_key UNIQUE (company_id);
  END IF;
END $$;

-- 3) Allow platform admins to read all companies + subscriptions
DROP POLICY IF EXISTS "platform admins read all companies" ON public.companies;
CREATE POLICY "platform admins read all companies" ON public.companies
  FOR SELECT TO authenticated
  USING (public.is_platform_admin(auth.uid()));

DROP POLICY IF EXISTS "platform admins update all companies" ON public.companies;
CREATE POLICY "platform admins update all companies" ON public.companies
  FOR UPDATE TO authenticated
  USING (public.is_platform_admin(auth.uid()));

DROP POLICY IF EXISTS "platform admins read all subscriptions" ON public.subscriptions;
CREATE POLICY "platform admins read all subscriptions" ON public.subscriptions
  FOR SELECT TO authenticated
  USING (public.is_platform_admin(auth.uid()));

DROP POLICY IF EXISTS "platform admins manage all subscriptions" ON public.subscriptions;
CREATE POLICY "platform admins manage all subscriptions" ON public.subscriptions
  FOR ALL TO authenticated
  USING (public.is_platform_admin(auth.uid()))
  WITH CHECK (public.is_platform_admin(auth.uid()));

DROP POLICY IF EXISTS "platform admins read all members" ON public.company_members;
CREATE POLICY "platform admins read all members" ON public.company_members
  FOR SELECT TO authenticated
  USING (public.is_platform_admin(auth.uid()));

DROP POLICY IF EXISTS "platform admins read all profiles" ON public.profiles;
CREATE POLICY "platform admins read all profiles" ON public.profiles
  FOR SELECT TO authenticated
  USING (public.is_platform_admin(auth.uid()));

-- 4) Grant: allow first user to be bootstrapped as platform admin if no admin exists
-- (Disabled by default - bootstrap manually via SQL)
