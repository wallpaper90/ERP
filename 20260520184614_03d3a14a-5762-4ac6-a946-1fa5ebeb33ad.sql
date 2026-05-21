
-- Update record_stock_movement to set a session flag allowing stock_qty UPDATE
CREATE OR REPLACE FUNCTION public.record_stock_movement(
  _company_id uuid, _product_id uuid, _type stock_movement_type,
  _quantity numeric, _reason text DEFAULT NULL::text,
  _ref_type text DEFAULT NULL::text, _ref_id uuid DEFAULT NULL::uuid
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE _id UUID; _delta NUMERIC;
BEGIN
  IF NOT public.is_company_member(auth.uid(), _company_id) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;

  _delta := CASE WHEN _type IN ('in','purchase','return','adjustment') THEN _quantity ELSE -_quantity END;

  INSERT INTO public.stock_movements(company_id, product_id, type, quantity, reason, reference_type, reference_id, created_by)
  VALUES (_company_id, _product_id, _type, _quantity, _reason, _ref_type, _ref_id, auth.uid())
  RETURNING id INTO _id;

  -- Allow this transaction to update stock_qty
  PERFORM set_config('app.allow_stock_update', 'true', true);

  UPDATE public.products SET stock_qty = stock_qty + _delta, updated_at = now()
  WHERE id = _product_id AND company_id = _company_id;

  RETURN _id;
END; $function$;

-- Trigger preventing direct stock_qty updates (except through record_stock_movement)
CREATE OR REPLACE FUNCTION public.guard_product_stock_qty()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path TO 'public'
AS $$
BEGIN
  IF NEW.stock_qty IS DISTINCT FROM OLD.stock_qty
     AND current_setting('app.allow_stock_update', true) IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'stock_qty cannot be updated directly; use record_stock_movement';
  END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_guard_product_stock_qty ON public.products;
CREATE TRIGGER trg_guard_product_stock_qty
  BEFORE UPDATE ON public.products
  FOR EACH ROW EXECUTE FUNCTION public.guard_product_stock_qty();

-- Helpful index for movements per product
CREATE INDEX IF NOT EXISTS idx_stock_movements_product_created
  ON public.stock_movements(product_id, created_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_stock_movements_company_created
  ON public.stock_movements(company_id, created_at DESC) WHERE deleted_at IS NULL;
