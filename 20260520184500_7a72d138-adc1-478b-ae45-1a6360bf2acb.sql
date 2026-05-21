CREATE INDEX IF NOT EXISTS idx_sales_company_date ON public.sales(company_id, invoice_date) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_sales_company_customer ON public.sales(company_id, customer_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_expenses_company_date ON public.expenses(company_id, expense_date) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_customers_company ON public.customers(company_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_products_company ON public.products(company_id) WHERE deleted_at IS NULL;