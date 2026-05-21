
CREATE OR REPLACE FUNCTION public.pos_validate_and_lock_stock(
  _company_id uuid,
  _items jsonb
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  r RECORD;
  _current NUMERIC;
  _name TEXT;
BEGIN
  IF NOT public.is_company_member(auth.uid(), _company_id) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;

  -- Lock all referenced products in deterministic order (id ASC) to avoid
  -- deadlocks between concurrent POS checkouts. Aggregate quantities per
  -- product_id in case the cart contains duplicates.
  FOR r IN
    SELECT (elem->>'product_id')::uuid AS product_id,
           SUM((elem->>'quantity')::numeric) AS qty
    FROM jsonb_array_elements(_items) AS elem
    WHERE elem->>'product_id' IS NOT NULL
    GROUP BY (elem->>'product_id')::uuid
    ORDER BY (elem->>'product_id')::uuid
  LOOP
    SELECT stock_qty, name INTO _current, _name
    FROM public.products
    WHERE id = r.product_id AND company_id = _company_id
    FOR UPDATE;

    IF _current IS NULL THEN
      RAISE EXCEPTION 'PRODUCT_NOT_FOUND: المنتج غير موجود (%)', r.product_id;
    END IF;
    IF _current < r.qty THEN
      RAISE EXCEPTION 'INSUFFICIENT_STOCK: المخزون غير كافٍ للمنتج "%" (المتاح: %, المطلوب: %)', _name, _current, r.qty;
    END IF;
  END LOOP;
END;
$$;

GRANT EXECUTE ON FUNCTION public.pos_validate_and_lock_stock(uuid, jsonb) TO authenticated;
