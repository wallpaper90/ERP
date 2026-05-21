
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'accountant';
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'employee';

-- Returns the (one) company_id assigned to a user, or NULL.
CREATE OR REPLACE FUNCTION public.get_user_primary_company(_user_id uuid)
RETURNS TABLE(company_id uuid, role public.app_role)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT cm.company_id, cm.role
  FROM public.company_members cm
  WHERE cm.user_id = _user_id
  ORDER BY cm.created_at ASC
  LIMIT 1;
$$;
