
-- ============== SALES RETURNS ==============
CREATE TABLE public.sales_returns (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL,
  sale_id UUID NOT NULL,
  customer_id UUID,
  return_number TEXT NOT NULL,
  return_date DATE NOT NULL DEFAULT CURRENT_DATE,
  reason TEXT,
  refund_amount NUMERIC NOT NULL DEFAULT 0,
  refund_method TEXT NOT NULL DEFAULT 'cash',
  notes TEXT,
  restock BOOLEAN NOT NULL DEFAULT true,
  created_by UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ
);

CREATE TABLE public.sales_return_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  return_id UUID NOT NULL REFERENCES public.sales_returns(id) ON DELETE CASCADE,
  product_id UUID,
  product_name TEXT NOT NULL,
  quantity NUMERIC NOT NULL DEFAULT 1,
  unit_price NUMERIC NOT NULL DEFAULT 0,
  total NUMERIC NOT NULL DEFAULT 0
);

ALTER TABLE public.sales_returns ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales_return_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "members rw sales_returns" ON public.sales_returns
  FOR ALL TO authenticated
  USING (is_company_member(auth.uid(), company_id))
  WITH CHECK (is_company_member(auth.uid(), company_id));

CREATE POLICY "members rw sales_return_items" ON public.sales_return_items
  FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.sales_returns r WHERE r.id = sales_return_items.return_id AND is_company_member(auth.uid(), r.company_id)))
  WITH CHECK (EXISTS (SELECT 1 FROM public.sales_returns r WHERE r.id = sales_return_items.return_id AND is_company_member(auth.uid(), r.company_id)));

CREATE TRIGGER set_sales_returns_updated_at BEFORE UPDATE ON public.sales_returns
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE INDEX idx_sales_returns_company ON public.sales_returns(company_id, return_date DESC);
CREATE INDEX idx_sales_returns_sale ON public.sales_returns(sale_id);
CREATE INDEX idx_sales_returns_customer ON public.sales_returns(customer_id);
CREATE INDEX idx_sales_return_items_return ON public.sales_return_items(return_id);

-- ============== PURCHASE RETURNS ==============
CREATE TABLE public.purchase_returns (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL,
  purchase_id UUID NOT NULL,
  supplier_id UUID,
  return_number TEXT NOT NULL,
  return_date DATE NOT NULL DEFAULT CURRENT_DATE,
  reason TEXT,
  total NUMERIC NOT NULL DEFAULT 0,
  notes TEXT,
  created_by UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ
);

CREATE TABLE public.purchase_return_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  return_id UUID NOT NULL REFERENCES public.purchase_returns(id) ON DELETE CASCADE,
  product_id UUID,
  product_name TEXT NOT NULL,
  quantity NUMERIC NOT NULL DEFAULT 1,
  unit_cost NUMERIC NOT NULL DEFAULT 0,
  total NUMERIC NOT NULL DEFAULT 0
);

ALTER TABLE public.purchase_returns ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_return_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "members rw purchase_returns" ON public.purchase_returns
  FOR ALL TO authenticated
  USING (is_company_member(auth.uid(), company_id))
  WITH CHECK (is_company_member(auth.uid(), company_id));

CREATE POLICY "members rw purchase_return_items" ON public.purchase_return_items
  FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.purchase_returns r WHERE r.id = purchase_return_items.return_id AND is_company_member(auth.uid(), r.company_id)))
  WITH CHECK (EXISTS (SELECT 1 FROM public.purchase_returns r WHERE r.id = purchase_return_items.return_id AND is_company_member(auth.uid(), r.company_id)));

CREATE TRIGGER set_purchase_returns_updated_at BEFORE UPDATE ON public.purchase_returns
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE INDEX idx_purchase_returns_company ON public.purchase_returns(company_id, return_date DESC);
CREATE INDEX idx_purchase_returns_purchase ON public.purchase_returns(purchase_id);
CREATE INDEX idx_purchase_returns_supplier ON public.purchase_returns(supplier_id);
CREATE INDEX idx_purchase_return_items_return ON public.purchase_return_items(return_id);

-- ============== RPCs (atomic with stock + balances) ==============

CREATE OR REPLACE FUNCTION public.create_sales_return(
  _company_id UUID,
  _sale_id UUID,
  _reason TEXT,
  _refund_amount NUMERIC,
  _refund_method TEXT,
  _restock BOOLEAN,
  _notes TEXT,
  _items JSONB  -- [{product_id, product_name, quantity, unit_price}]
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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

  -- Validate quantities per item
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

  -- Generate return number
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

  -- Insert items + restock
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

  -- Adjust customer balance (decrease what they owe by refund amount)
  IF _customer_id IS NOT NULL AND COALESCE(_refund_amount,0) > 0 THEN
    UPDATE public.customers SET balance = balance - _refund_amount, updated_at = now()
      WHERE id = _customer_id AND company_id = _company_id;
  END IF;

  RETURN _return_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_purchase_return(
  _company_id UUID,
  _purchase_id UUID,
  _reason TEXT,
  _notes TEXT,
  _items JSONB  -- [{product_id, product_name, quantity, unit_cost}]
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _return_id UUID;
  _return_number TEXT;
  _supplier_id UUID;
  _item JSONB;
  _qty NUMERIC;
  _purchased_qty NUMERIC;
  _returned_qty NUMERIC;
  _total NUMERIC := 0;
  _line_total NUMERIC;
BEGIN
  IF NOT public.is_company_member(auth.uid(), _company_id) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;

  SELECT supplier_id INTO _supplier_id FROM public.purchases
    WHERE id = _purchase_id AND company_id = _company_id AND deleted_at IS NULL;
  IF NOT FOUND THEN RAISE EXCEPTION 'Purchase not found'; END IF;

  -- Validate quantities
  FOR _item IN SELECT * FROM jsonb_array_elements(_items) LOOP
    _qty := (_item->>'quantity')::NUMERIC;
    IF _qty <= 0 THEN CONTINUE; END IF;

    IF (_item->>'product_id') IS NOT NULL THEN
      SELECT COALESCE(SUM(quantity), 0) INTO _purchased_qty
        FROM public.purchase_items
        WHERE purchase_id = _purchase_id AND product_id = (_item->>'product_id')::UUID;

      SELECT COALESCE(SUM(pri.quantity), 0) INTO _returned_qty
        FROM public.purchase_return_items pri
        JOIN public.purchase_returns pr ON pr.id = pri.return_id
        WHERE pr.purchase_id = _purchase_id AND pr.deleted_at IS NULL
          AND pri.product_id = (_item->>'product_id')::UUID;

      IF _qty + _returned_qty > _purchased_qty THEN
        RAISE EXCEPTION 'Return quantity exceeds purchased quantity for product %', _item->>'product_name';
      END IF;
    END IF;
  END LOOP;

  SELECT 'PR-' || TO_CHAR(now(), 'YYYYMMDD') || '-' || LPAD((COUNT(*) + 1)::TEXT, 4, '0')
    INTO _return_number
    FROM public.purchase_returns
    WHERE company_id = _company_id AND return_date = CURRENT_DATE;

  INSERT INTO public.purchase_returns(
    company_id, purchase_id, supplier_id, return_number, reason, notes, created_by, total
  ) VALUES (
    _company_id, _purchase_id, _supplier_id, _return_number, _reason, _notes, auth.uid(), 0
  ) RETURNING id INTO _return_id;

  FOR _item IN SELECT * FROM jsonb_array_elements(_items) LOOP
    _qty := (_item->>'quantity')::NUMERIC;
    IF _qty <= 0 THEN CONTINUE; END IF;

    _line_total := _qty * COALESCE((_item->>'unit_cost')::NUMERIC, 0);
    _total := _total + _line_total;

    INSERT INTO public.purchase_return_items(
      return_id, product_id, product_name, quantity, unit_cost, total
    ) VALUES (
      _return_id,
      NULLIF(_item->>'product_id','')::UUID,
      _item->>'product_name',
      _qty,
      COALESCE((_item->>'unit_cost')::NUMERIC, 0),
      _line_total
    );

    IF (_item->>'product_id') IS NOT NULL THEN
      PERFORM public.record_stock_movement(
        _company_id, (_item->>'product_id')::UUID, 'out'::stock_movement_type,
        _qty, 'Purchase return', 'purchase_return', _return_id
      );
    END IF;
  END LOOP;

  UPDATE public.purchase_returns SET total = _total WHERE id = _return_id;

  -- Adjust supplier balance (we owe them less)
  IF _supplier_id IS NOT NULL AND _total > 0 THEN
    UPDATE public.suppliers SET balance = balance - _total, updated_at = now()
      WHERE id = _supplier_id AND company_id = _company_id;
  END IF;

  RETURN _return_id;
END;
$$;
