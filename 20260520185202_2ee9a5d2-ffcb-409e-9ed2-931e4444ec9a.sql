ALTER TYPE sale_status ADD VALUE IF NOT EXISTS 'sent';
ALTER TYPE sale_status ADD VALUE IF NOT EXISTS 'overdue';

ALTER TABLE public.sales ADD COLUMN IF NOT EXISTS due_date date;