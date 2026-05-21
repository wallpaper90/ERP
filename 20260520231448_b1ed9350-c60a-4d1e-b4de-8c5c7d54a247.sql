
-- 1) Tighten storage policies on company-logos bucket
DROP POLICY IF EXISTS "company-logos read" ON storage.objects;
DROP POLICY IF EXISTS "public read company-logos" ON storage.objects;

CREATE POLICY "company-logos members list"
ON storage.objects FOR SELECT
TO authenticated
USING (
  bucket_id = 'company-logos'
  AND (storage.foldername(name))[1] IS NOT NULL
  AND public.is_company_member(auth.uid(), ((storage.foldername(name))[1])::uuid)
);

-- 2) RPC: assign existing user to a company with a role (platform admin only)
CREATE OR REPLACE FUNCTION public.assign_user_to_company(
  _user_id uuid,
  _company_id uuid,
  _role app_role
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_platform_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Only platform admins can assign users';
  END IF;

  INSERT INTO public.company_members(user_id, company_id, role)
  VALUES (_user_id, _company_id, _role)
  ON CONFLICT (user_id, company_id) DO UPDATE SET role = EXCLUDED.role;
END;
$$;

-- 3) RPC: remove user from company (platform admin only)
CREATE OR REPLACE FUNCTION public.remove_user_from_company(
  _user_id uuid,
  _company_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_platform_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Only platform admins can remove users';
  END IF;

  DELETE FROM public.company_members
   WHERE user_id = _user_id AND company_id = _company_id;
END;
$$;

-- 4) RPC: create company and assign user as owner (platform admin only)
CREATE OR REPLACE FUNCTION public.create_company_for_user(
  _user_id uuid,
  _company_name text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE _company_id uuid;
BEGIN
  IF NOT public.is_platform_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Only platform admins can create companies for users';
  END IF;

  INSERT INTO public.companies(name, created_by)
  VALUES (_company_name, _user_id)
  RETURNING id INTO _company_id;

  INSERT INTO public.company_members(user_id, company_id, role)
  VALUES (_user_id, _company_id, 'owner');

  INSERT INTO public.subscriptions(company_id, plan, status)
  VALUES (_company_id, 'trial', 'active')
  ON CONFLICT (company_id) DO NOTHING;

  RETURN _company_id;
END;
$$;

-- 5) Add unique constraint on company_members so ON CONFLICT works
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'company_members_user_company_uniq'
  ) THEN
    ALTER TABLE public.company_members
      ADD CONSTRAINT company_members_user_company_uniq UNIQUE (user_id, company_id);
  END IF;
END $$;
