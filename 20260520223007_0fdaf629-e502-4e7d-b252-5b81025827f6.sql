DO $$
DECLARE t text;
BEGIN
  FOR t IN SELECT unnest(ARRAY['sales','sale_items','pos_orders','pos_order_items','payments','purchases','purchase_items','products','stock_movements','expenses']) LOOP
    EXECUTE format('ALTER TABLE public.%I REPLICA IDENTITY FULL', t);
    BEGIN
      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', t);
    EXCEPTION WHEN duplicate_object THEN NULL;
    END;
  END LOOP;
END $$;