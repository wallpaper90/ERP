
-- Fix search_path on remaining functions
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;

-- Revoke execute from public/anon on security definer helpers
REVOKE EXECUTE ON FUNCTION public.get_user_company_ids(UUID) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.is_company_member(UUID, UUID) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.has_company_role(UUID, UUID, app_role[]) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;
