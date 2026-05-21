
CREATE OR REPLACE FUNCTION public.create_sale_tx(
  _company_id uuid,
  _invoice_number text,
  _invoice_date date,
  _status sale_status,
  _items jsonb,
  _customer_id uuid DEFAULT NULL,
  _due_date date DEFAULT NULL,
  _discount numeric DEFAULT 0,
  _notes text DEFAULT NULL,
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
    subtotal, tax_amount, discount, total, status, notes, created_by, paid_amount
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

    IF _pid IS NOT NULL AND _status <> 'draft' THEN
      PERFORM public.record_stock_movement(
        _company_id, _pid, 'sale'::stock_movement_type,
        _qty, 'Sale ' || _invoice_number, 'sale', _sale_id
      );
    END IF;
  END LOOP;

  IF _customer_id IS NOT NULL AND _status <> 'draft' THEN
    UPDATE public.customers
      SET balance = balance + (_total - LEAST(COALESCE(_payment_amount,0), _total)),
          updated_at = now()
      WHERE id = _customer_id AND company_id = _company_id;
  END IF;

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

-- Drop the previous variant (different signature) to avoid ambiguity
DROP FUNCTION IF EXISTS public.create_sale_tx(uuid, uuid, text, date, date, numeric, sale_status, text, jsonb, numeric, text);
