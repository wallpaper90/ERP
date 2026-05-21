-- 1. Extend companies with extra profile fields
ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS logo_url text,
  ADD COLUMN IF NOT EXISTS commercial_registration text,
  ADD COLUMN IF NOT EXISTS email text,
  ADD COLUMN IF NOT EXISTS language text NOT NULL DEFAULT 'ar',
  ADD COLUMN IF NOT EXISTS timezone text NOT NULL DEFAULT 'Asia/Riyadh',
  ADD COLUMN IF NOT EXISTS date_format text NOT NULL DEFAULT 'YYYY-MM-DD';

-- 2. company_settings (one row per company, flexible JSON sections)
CREATE TABLE IF NOT EXISTS public.company_settings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL UNIQUE,
  print jsonb NOT NULL DEFAULT jsonb_build_object(
    'paper_size','A4',
    'template','modern',
    'logo_position','right',
    'footer_text','شكراً لتعاملكم معنا',
    'show_signature', true
  ),
  invoice jsonb NOT NULL DEFAULT jsonb_build_object(
    'prefix','INV',
    'numbering','yearly',
    'next_number', 1,
    'auto_due_days', 14,
    'default_tax_rate', 15,
    'payment_terms','الدفع خلال 14 يوم من تاريخ الفاتورة'
  ),
  ui jsonb NOT NULL DEFAULT jsonb_build_object(
    'theme','system',
    'sidebar','expanded',
    'compact', false,
    'dashboard_layout','default'
  ),
  permissions jsonb NOT NULL DEFAULT jsonb_build_object(
    'accountant', jsonb_build_array('sales','purchases','payments','expenses','reports'),
    'employee',   jsonb_build_array('sales','customers','products')
  ),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "members read company_settings"
  ON public.company_settings FOR SELECT TO authenticated
  USING (public.is_company_member(auth.uid(), company_id));

CREATE POLICY "members insert company_settings"
  ON public.company_settings FOR INSERT TO authenticated
  WITH CHECK (public.is_company_member(auth.uid(), company_id));

CREATE POLICY "owners update company_settings"
  ON public.company_settings FOR UPDATE TO authenticated
  USING (public.has_company_role(auth.uid(), company_id, ARRAY['owner'::app_role,'admin'::app_role]))
  WITH CHECK (public.has_company_role(auth.uid(), company_id, ARRAY['owner'::app_role,'admin'::app_role]));

CREATE TRIGGER company_settings_updated_at
  BEFORE UPDATE ON public.company_settings
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE INDEX IF NOT EXISTS idx_company_settings_company_id ON public.company_settings(company_id);

-- 3. Public bucket for company logos
INSERT INTO storage.buckets (id, name, public)
VALUES ('company-logos','company-logos', true)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "public read company-logos"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'company-logos');

CREATE POLICY "company members upload logos"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'company-logos'
    AND public.is_company_member(auth.uid(), ((storage.foldername(name))[1])::uuid)
  );

CREATE POLICY "company admins update logos"
  ON storage.objects FOR UPDATE TO authenticated
  USING (
    bucket_id = 'company-logos'
    AND public.has_company_role(auth.uid(), ((storage.foldername(name))[1])::uuid, ARRAY['owner'::app_role,'admin'::app_role])
  );

CREATE POLICY "company admins delete logos"
  ON storage.objects FOR DELETE TO authenticated
  USING (
    bucket_id = 'company-logos'
    AND public.has_company_role(auth.uid(), ((storage.foldername(name))[1])::uuid, ARRAY['owner'::app_role,'admin'::app_role])
  );