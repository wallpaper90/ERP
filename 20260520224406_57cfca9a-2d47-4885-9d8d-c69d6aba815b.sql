
-- 1) Prevent negative stock for outbound movements
CREATE OR REPLACE FUNCTION public.record_stock_movement(
  _company_id uuid, _product_id uuid, _type stock_movement_type,
  _quantity numeric, _reason text DEFAULT NULL, _ref_type text DEFAULT NULL, _ref_id uuid DEFAULT NULL
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE _id UUID; _delta NUMERIC; _current NUMERIC;
BEGIN
  IF NOT public.is_company_member(auth.uid(), _company_id) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;

  _delta := CASE WHEN _type IN ('in','purchase','return','adjustment') THEN _quantity ELSE -_quantity END;

  IF _delta < 0 THEN
    SELECT stock_qty INTO _current FROM public.products
      WHERE id = _product_id AND company_id = _company_id FOR UPDATE;
    IF COALESCE(_current,0) + _delta < 0 THEN
      RAISE EXCEPTION 'INSUFFICIENT_STOCK: المخزون غير كافٍ (المتاح: %, المطلوب: %)', COALESCE(_current,0), _quantity;
    END IF;
  END IF;

  INSERT INTO public.stock_movements(company_id, product_id, type, quantity, reason, reference_type, reference_id, created_by)
  VALUES (_company_id, _product_id, _type, _quantity, _reason, _ref_type, _ref_id, auth.uid())
  RETURNING id INTO _id;

  PERFORM set_config('app.allow_stock_update', 'true', true);
  UPDATE public.products SET stock_qty = stock_qty + _delta, updated_at = now()
    WHERE id = _product_id AND company_id = _company_id;

  RETURN _id;
END; $$;

-- 2) Atomic invoice creation transaction
CREATE OR REPLACE FUNCTION public.create_sale_tx(
  _company_id uuid,
  _customer_id uuid,
  _invoice_number text,
  _invoice_date date,
  _due_date date,
  _discount numeric,
  _status sale_status,
  _notes text,
  _items jsonb,
  _payment_amount numeric DEFAULT 0,
  _payment_method text DEFAULT 'cash'
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  _sale_id uuid;
  _it jsonb;
  _subtotal numeric := 0;
  _tax numeric := 0;
  _total numeric := 0;
  _line numeric;
  _line_tax numeric;
  _qty numeric;
  _price numeric;
  _rate numeric;
  _pid uuid;
BEGIN
  IF NOT public.is_company_member(auth.uid(), _company_id) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;

  -- Compute totals server-side
  FOR _it IN SELECT * FROM jsonb_array_elements(_items) LOOP
    _qty := COALESCE((_it->>'quantity')::numeric, 0);
    _price := COALESCE((_it->>'unit_price')::numeric, 0);
    _rate := COALESCE((_it->>'tax_rate')::numeric, 15);
    _line := _qty * _price;
    _line_tax := _line * _rate / 100;
    _subtotal := _subtotal + _line;
    _tax := _tax + _line_tax;
  END LOOP;
  _total := _subtotal + _tax - COALESCE(_discount,0);

  INSERT INTO public.sales(
    company_id, customer_id, invoice_number, invoice_date, due_date,
    subtotal, tax_amount, discount, total, status, notes, created_by,
    paid_amount
  ) VALUES (
    _company_id, _customer_id, _invoice_number, _invoice_date, _due_date,
    _subtotal, _tax, COALESCE(_discount,0), _total, _status, _notes, auth.uid(),
    LEAST(COALESCE(_payment_amount,0), _total)
  ) RETURNING id INTO _sale_id;

  FOR _it IN SELECT * FROM jsonb_array_elements(_items) LOOP
    _qty := COALESCE((_it->>'quantity')::numeric, 0);
    _price := COALESCE((_it->>'unit_price')::numeric, 0);
    _rate := COALESCE((_it->>'tax_rate')::numeric, 15);
    _line := _qty * _price;
    _line_tax := _line * _rate / 100;
    _pid := NULLIF(_it->>'product_id','')::uuid;

    INSERT INTO public.sale_items(sale_id, product_id, product_name, quantity, unit_price, tax_rate, total)
    VALUES (_sale_id, _pid, _it->>'product_name', _qty, _price, _rate, _line + _line_tax);

    -- Deduct stock atomically (raises if insufficient)
    IF _pid IS NOT NULL AND _status <> 'draft' THEN
      PERFORM public.record_stock_movement(
        _company_id, _pid, 'sale'::stock_movement_type,
        _qty, 'Sale ' || _invoice_number, 'sale', _sale_id
      );
    END IF;
  END LOOP;

  -- Update customer balance for unpaid portion
  IF _customer_id IS NOT NULL AND _status <> 'draft' THEN
    UPDATE public.customers
      SET balance = balance + (_total - LEAST(COALESCE(_payment_amount,0), _total)),
          updated_at = now()
      WHERE id = _customer_id AND company_id = _company_id;
  END IF;

  -- Register payment if provided
  IF COALESCE(_payment_amount,0) > 0 AND _status <> 'draft' THEN
    INSERT INTO public.payments(company_id, sale_id, customer_id, direction, amount, method, created_by)
    VALUES (_company_id, _sale_id, _customer_id, 'in'::payment_direction,
            LEAST(_payment_amount, _total), _payment_method, auth.uid());

    IF LEAST(_payment_amount, _total) >= _total THEN
      UPDATE public.sales SET status = 'paid' WHERE id = _sale_id;
    END IF;
  END IF;

  RETURN _sale_id;
END; $$;
