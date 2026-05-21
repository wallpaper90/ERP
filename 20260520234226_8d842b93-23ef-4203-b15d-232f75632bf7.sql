-- 1) Immutable event log
CREATE TABLE IF NOT EXISTS public.domain_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL,
  event_name text NOT NULL,
  aggregate_type text NOT NULL,
  aggregate_id uuid,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid
);

CREATE INDEX IF NOT EXISTS idx_domain_events_company_created
  ON public.domain_events (company_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_domain_events_name
  ON public.domain_events (company_id, event_name, created_at DESC);

ALTER TABLE public.domain_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "members read domain_events"
  ON public.domain_events FOR SELECT TO authenticated
  USING (public.is_company_member(auth.uid(), company_id));

-- No INSERT/UPDATE/DELETE policies => only SECURITY DEFINER triggers write.

ALTER PUBLICATION supabase_realtime ADD TABLE public.domain_events;
ALTER TABLE public.domain_events REPLICA IDENTITY FULL;

-- 2) Publisher helper
CREATE OR REPLACE FUNCTION public.publish_event(
  _company_id uuid, _event_name text, _aggregate_type text,
  _aggregate_id uuid, _payload jsonb
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _id uuid;
BEGIN
  IF _company_id IS NULL THEN RETURN NULL; END IF;
  INSERT INTO public.domain_events(company_id, event_name, aggregate_type, aggregate_id, payload, created_by)
  VALUES (_company_id, _event_name, _aggregate_type, _aggregate_id, COALESCE(_payload,'{}'::jsonb), auth.uid())
  RETURNING id INTO _id;
  RETURN _id;
END $$;

-- 3) Trigger functions
CREATE OR REPLACE FUNCTION public.evt_on_sale() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    PERFORM public.publish_event(NEW.company_id, 'invoice.created', 'sale', NEW.id,
      jsonb_build_object('invoice_number', NEW.invoice_number, 'total', NEW.total, 'customer_id', NEW.customer_id, 'status', NEW.status));
  ELSIF TG_OP = 'UPDATE' THEN
    IF NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL THEN
      PERFORM public.publish_event(NEW.company_id, 'invoice.deleted', 'sale', NEW.id,
        jsonb_build_object('invoice_number', NEW.invoice_number));
    ELSIF NEW.status IS DISTINCT FROM OLD.status THEN
      PERFORM public.publish_event(NEW.company_id, 'invoice.status_changed', 'sale', NEW.id,
        jsonb_build_object('invoice_number', NEW.invoice_number, 'old_status', OLD.status, 'new_status', NEW.status));
    END IF;
  END IF;
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION public.evt_on_purchase() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    PERFORM public.publish_event(NEW.company_id, 'purchase.created', 'purchase', NEW.id,
      jsonb_build_object('invoice_number', NEW.invoice_number, 'total', NEW.total, 'supplier_id', NEW.supplier_id));
  ELSIF TG_OP = 'UPDATE' AND NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL THEN
    PERFORM public.publish_event(NEW.company_id, 'purchase.deleted', 'purchase', NEW.id, jsonb_build_object('invoice_number', NEW.invoice_number));
  END IF;
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION public.evt_on_payment() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    PERFORM public.publish_event(NEW.company_id, 'payment.added', 'payment', NEW.id,
      jsonb_build_object('direction', NEW.direction, 'amount', NEW.amount, 'method', NEW.method,
        'customer_id', NEW.customer_id, 'supplier_id', NEW.supplier_id, 'sale_id', NEW.sale_id, 'purchase_id', NEW.purchase_id));
  END IF;
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION public.evt_on_stock_movement() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    PERFORM public.publish_event(NEW.company_id, 'stock.updated', 'product', NEW.product_id,
      jsonb_build_object('type', NEW.type, 'quantity', NEW.quantity, 'reference_type', NEW.reference_type, 'reference_id', NEW.reference_id));
  END IF;
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION public.evt_on_pos_order() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    PERFORM public.publish_event(NEW.company_id, 'pos.order.created', 'pos_order', NEW.id,
      jsonb_build_object('order_number', NEW.order_number, 'total', NEW.total, 'payment_method', NEW.payment_method));
  ELSIF TG_OP = 'UPDATE' AND NEW.status = 'voided' AND OLD.status IS DISTINCT FROM 'voided' THEN
    PERFORM public.publish_event(NEW.company_id, 'pos.order.voided', 'pos_order', NEW.id, jsonb_build_object('order_number', NEW.order_number));
  END IF;
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION public.evt_on_expense() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    PERFORM public.publish_event(NEW.company_id, 'expense.added', 'expense', NEW.id,
      jsonb_build_object('amount', NEW.amount, 'category_id', NEW.category_id, 'method', NEW.payment_method));
  END IF;
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION public.evt_on_sales_return() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    PERFORM public.publish_event(NEW.company_id, 'sales_return.created', 'sales_return', NEW.id,
      jsonb_build_object('return_number', NEW.return_number, 'refund_amount', NEW.refund_amount, 'sale_id', NEW.sale_id));
  END IF;
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION public.evt_on_purchase_return() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    PERFORM public.publish_event(NEW.company_id, 'purchase_return.created', 'purchase_return', NEW.id,
      jsonb_build_object('return_number', NEW.return_number, 'total', NEW.total, 'purchase_id', NEW.purchase_id));
  END IF;
  RETURN NEW;
END $$;

-- 4) Attach triggers (drop+recreate idempotent)
DROP TRIGGER IF EXISTS trg_evt_sale ON public.sales;
CREATE TRIGGER trg_evt_sale AFTER INSERT OR UPDATE ON public.sales
  FOR EACH ROW EXECUTE FUNCTION public.evt_on_sale();

DROP TRIGGER IF EXISTS trg_evt_purchase ON public.purchases;
CREATE TRIGGER trg_evt_purchase AFTER INSERT OR UPDATE ON public.purchases
  FOR EACH ROW EXECUTE FUNCTION public.evt_on_purchase();

DROP TRIGGER IF EXISTS trg_evt_payment ON public.payments;
CREATE TRIGGER trg_evt_payment AFTER INSERT ON public.payments
  FOR EACH ROW EXECUTE FUNCTION public.evt_on_payment();

DROP TRIGGER IF EXISTS trg_evt_stock ON public.stock_movements;
CREATE TRIGGER trg_evt_stock AFTER INSERT ON public.stock_movements
  FOR EACH ROW EXECUTE FUNCTION public.evt_on_stock_movement();

DROP TRIGGER IF EXISTS trg_evt_pos_order ON public.pos_orders;
CREATE TRIGGER trg_evt_pos_order AFTER INSERT OR UPDATE ON public.pos_orders
  FOR EACH ROW EXECUTE FUNCTION public.evt_on_pos_order();

DROP TRIGGER IF EXISTS trg_evt_expense ON public.expenses;
CREATE TRIGGER trg_evt_expense AFTER INSERT ON public.expenses
  FOR EACH ROW EXECUTE FUNCTION public.evt_on_expense();

DROP TRIGGER IF EXISTS trg_evt_sales_return ON public.sales_returns;
CREATE TRIGGER trg_evt_sales_return AFTER INSERT ON public.sales_returns
  FOR EACH ROW EXECUTE FUNCTION public.evt_on_sales_return();

DROP TRIGGER IF EXISTS trg_evt_purchase_return ON public.purchase_returns;
CREATE TRIGGER trg_evt_purchase_return AFTER INSERT ON public.purchase_returns
  FOR EACH ROW EXECUTE FUNCTION public.evt_on_purchase_return();