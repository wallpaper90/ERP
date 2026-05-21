
-- Revoke EXECUTE from anon/public for all SECURITY DEFINER functions in public schema.
-- Authenticated role still has access via default grants.
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT n.nspname, p.proname, pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prosecdef = true
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %I.%I(%s) FROM PUBLIC, anon;', r.nspname, r.proname, r.args);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %I.%I(%s) TO authenticated;', r.nspname, r.proname, r.args);
  END LOOP;
END $$;

-- Tighten company-logos bucket: only company members can write; reads stay public.
DROP POLICY IF EXISTS "company-logos public read" ON storage.objects;
DROP POLICY IF EXISTS "company-logos read" ON storage.objects;
DROP POLICY IF EXISTS "company-logos write" ON storage.objects;
DROP POLICY IF EXISTS "company-logos members write" ON storage.objects;
DROP POLICY IF EXISTS "company-logos members update" ON storage.objects;
DROP POLICY IF EXISTS "company-logos members delete" ON storage.objects;

CREATE POLICY "company-logos read"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'company-logos');

CREATE POLICY "company-logos members write"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'company-logos'
    AND (storage.foldername(name))[1] IS NOT NULL
    AND public.is_company_member(auth.uid(), ((storage.foldername(name))[1])::uuid)
  );

CREATE POLICY "company-logos members update"
  ON storage.objects FOR UPDATE TO authenticated
  USING (
    bucket_id = 'company-logos'
    AND public.is_company_member(auth.uid(), ((storage.foldername(name))[1])::uuid)
  );

CREATE POLICY "company-logos members delete"
  ON storage.objects FOR DELETE TO authenticated
  USING (
    bucket_id = 'company-logos'
    AND public.is_company_member(auth.uid(), ((storage.foldername(name))[1])::uuid)
  );
