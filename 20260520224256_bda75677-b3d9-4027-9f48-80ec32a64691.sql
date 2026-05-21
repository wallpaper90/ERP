DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename='customers') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.customers;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename='suppliers') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.suppliers;
  END IF;
END $$;
ALTER TABLE public.customers REPLICA IDENTITY FULL;
ALTER TABLE public.suppliers REPLICA IDENTITY FULL;