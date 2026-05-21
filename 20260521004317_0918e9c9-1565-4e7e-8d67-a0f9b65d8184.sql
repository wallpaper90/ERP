-- 1) Promote pepo4graphic@gmail.com to platform admin (owner of the program)
INSERT INTO public.platform_admins (user_id)
SELECT id FROM auth.users WHERE email = 'pepo4graphic@gmail.com'
ON CONFLICT DO NOTHING;

-- 2) Add 'lifetime' option to subscription_plan enum
ALTER TYPE public.subscription_plan ADD VALUE IF NOT EXISTS 'lifetime';