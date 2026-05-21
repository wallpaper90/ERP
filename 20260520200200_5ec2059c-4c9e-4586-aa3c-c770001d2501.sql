DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'expenses_category_id_fkey') THEN
    ALTER TABLE public.expenses ADD CONSTRAINT expenses_category_id_fkey
      FOREIGN KEY (category_id) REFERENCES public.expense_categories(id) ON DELETE SET NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'payments_customer_id_fkey') THEN
    ALTER TABLE public.payments ADD CONSTRAINT payments_customer_id_fkey
      FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE SET NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'payments_supplier_id_fkey') THEN
    ALTER TABLE public.payments ADD CONSTRAINT payments_supplier_id_fkey
      FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id) ON DELETE SET NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'payments_sale_id_fkey') THEN
    ALTER TABLE public.payments ADD CONSTRAINT payments_sale_id_fkey
      FOREIGN KEY (sale_id) REFERENCES public.sales(id) ON DELETE SET NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'payments_purchase_id_fkey') THEN
    ALTER TABLE public.payments ADD CONSTRAINT payments_purchase_id_fkey
      FOREIGN KEY (purchase_id) REFERENCES public.purchases(id) ON DELETE SET NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'sales_customer_id_fkey') THEN
    ALTER TABLE public.sales ADD CONSTRAINT sales_customer_id_fkey
      FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE SET NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'purchases_supplier_id_fkey') THEN
    ALTER TABLE public.purchases ADD CONSTRAINT purchases_supplier_id_fkey
      FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id) ON DELETE SET NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_sales_company_date ON public.sales(company_id, invoice_date DESC) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_purchases_company_date ON public.purchases(company_id, invoice_date DESC) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_expenses_company_date ON public.expenses(company_id, expense_date DESC) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_payments_company_date ON public.payments(company_id, payment_date DESC) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_sales_customer ON public.sales(customer_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_purchases_supplier ON public.purchases(supplier_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_expenses_category ON public.expenses(category_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_payments_customer ON public.payments(customer_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_payments_supplier ON public.payments(supplier_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_sale_items_product ON public.sale_items(product_id);
CREATE INDEX IF NOT EXISTS idx_purchase_items_product ON public.purchase_items(product_id);