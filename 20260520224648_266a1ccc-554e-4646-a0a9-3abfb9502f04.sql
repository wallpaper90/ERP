
-- Helper: add FK only if missing
DO $$
DECLARE
  r record;
BEGIN
  -- sales -> companies, customers
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='sales_company_id_fkey') THEN
    ALTER TABLE public.sales ADD CONSTRAINT sales_company_id_fkey
      FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='sales_customer_id_fkey') THEN
    ALTER TABLE public.sales ADD CONSTRAINT sales_customer_id_fkey
      FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE SET NULL;
  END IF;

  -- sale_items -> sales, products
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='sale_items_sale_id_fkey') THEN
    ALTER TABLE public.sale_items ADD CONSTRAINT sale_items_sale_id_fkey
      FOREIGN KEY (sale_id) REFERENCES public.sales(id) ON DELETE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='sale_items_product_id_fkey') THEN
    ALTER TABLE public.sale_items ADD CONSTRAINT sale_items_product_id_fkey
      FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE SET NULL;
  END IF;

  -- payments -> companies, sales, customers, suppliers, purchases
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='payments_company_id_fkey') THEN
    ALTER TABLE public.payments ADD CONSTRAINT payments_company_id_fkey
      FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='payments_sale_id_fkey') THEN
    ALTER TABLE public.payments ADD CONSTRAINT payments_sale_id_fkey
      FOREIGN KEY (sale_id) REFERENCES public.sales(id) ON DELETE SET NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='payments_customer_id_fkey') THEN
    ALTER TABLE public.payments ADD CONSTRAINT payments_customer_id_fkey
      FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE SET NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='payments_supplier_id_fkey') THEN
    ALTER TABLE public.payments ADD CONSTRAINT payments_supplier_id_fkey
      FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id) ON DELETE SET NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='payments_purchase_id_fkey') THEN
    ALTER TABLE public.payments ADD CONSTRAINT payments_purchase_id_fkey
      FOREIGN KEY (purchase_id) REFERENCES public.purchases(id) ON DELETE SET NULL;
  END IF;

  -- stock_movements -> companies, products
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='stock_movements_company_id_fkey') THEN
    ALTER TABLE public.stock_movements ADD CONSTRAINT stock_movements_company_id_fkey
      FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='stock_movements_product_id_fkey') THEN
    ALTER TABLE public.stock_movements ADD CONSTRAINT stock_movements_product_id_fkey
      FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE;
  END IF;

  -- products -> companies, categories
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='products_company_id_fkey') THEN
    ALTER TABLE public.products ADD CONSTRAINT products_company_id_fkey
      FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='products_category_id_fkey') THEN
    ALTER TABLE public.products ADD CONSTRAINT products_category_id_fkey
      FOREIGN KEY (category_id) REFERENCES public.categories(id) ON DELETE SET NULL;
  END IF;

  -- categories -> companies
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='categories_company_id_fkey') THEN
    ALTER TABLE public.categories ADD CONSTRAINT categories_company_id_fkey
      FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
  END IF;

  -- customers/suppliers -> companies
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='customers_company_id_fkey') THEN
    ALTER TABLE public.customers ADD CONSTRAINT customers_company_id_fkey
      FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='suppliers_company_id_fkey') THEN
    ALTER TABLE public.suppliers ADD CONSTRAINT suppliers_company_id_fkey
      FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
  END IF;

  -- purchases -> companies, suppliers
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='purchases_company_id_fkey') THEN
    ALTER TABLE public.purchases ADD CONSTRAINT purchases_company_id_fkey
      FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='purchases_supplier_id_fkey') THEN
    ALTER TABLE public.purchases ADD CONSTRAINT purchases_supplier_id_fkey
      FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id) ON DELETE SET NULL;
  END IF;

  -- purchase_items -> purchases, products
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='purchase_items_purchase_id_fkey') THEN
    ALTER TABLE public.purchase_items ADD CONSTRAINT purchase_items_purchase_id_fkey
      FOREIGN KEY (purchase_id) REFERENCES public.purchases(id) ON DELETE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='purchase_items_product_id_fkey') THEN
    ALTER TABLE public.purchase_items ADD CONSTRAINT purchase_items_product_id_fkey
      FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE SET NULL;
  END IF;

  -- sales_returns / purchase_returns
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='sales_returns_company_id_fkey') THEN
    ALTER TABLE public.sales_returns ADD CONSTRAINT sales_returns_company_id_fkey
      FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='sales_returns_sale_id_fkey') THEN
    ALTER TABLE public.sales_returns ADD CONSTRAINT sales_returns_sale_id_fkey
      FOREIGN KEY (sale_id) REFERENCES public.sales(id) ON DELETE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='sales_returns_customer_id_fkey') THEN
    ALTER TABLE public.sales_returns ADD CONSTRAINT sales_returns_customer_id_fkey
      FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE SET NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='sales_return_items_return_id_fkey') THEN
    ALTER TABLE public.sales_return_items ADD CONSTRAINT sales_return_items_return_id_fkey
      FOREIGN KEY (return_id) REFERENCES public.sales_returns(id) ON DELETE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='sales_return_items_product_id_fkey') THEN
    ALTER TABLE public.sales_return_items ADD CONSTRAINT sales_return_items_product_id_fkey
      FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE SET NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='purchase_returns_company_id_fkey') THEN
    ALTER TABLE public.purchase_returns ADD CONSTRAINT purchase_returns_company_id_fkey
      FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='purchase_returns_purchase_id_fkey') THEN
    ALTER TABLE public.purchase_returns ADD CONSTRAINT purchase_returns_purchase_id_fkey
      FOREIGN KEY (purchase_id) REFERENCES public.purchases(id) ON DELETE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='purchase_returns_supplier_id_fkey') THEN
    ALTER TABLE public.purchase_returns ADD CONSTRAINT purchase_returns_supplier_id_fkey
      FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id) ON DELETE SET NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='purchase_return_items_return_id_fkey') THEN
    ALTER TABLE public.purchase_return_items ADD CONSTRAINT purchase_return_items_return_id_fkey
      FOREIGN KEY (return_id) REFERENCES public.purchase_returns(id) ON DELETE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='purchase_return_items_product_id_fkey') THEN
    ALTER TABLE public.purchase_return_items ADD CONSTRAINT purchase_return_items_product_id_fkey
      FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE SET NULL;
  END IF;

  -- POS
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='pos_orders_company_id_fkey') THEN
    ALTER TABLE public.pos_orders ADD CONSTRAINT pos_orders_company_id_fkey
      FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='pos_orders_customer_id_fkey') THEN
    ALTER TABLE public.pos_orders ADD CONSTRAINT pos_orders_customer_id_fkey
      FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE SET NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='pos_orders_session_id_fkey') THEN
    ALTER TABLE public.pos_orders ADD CONSTRAINT pos_orders_session_id_fkey
      FOREIGN KEY (session_id) REFERENCES public.pos_sessions(id) ON DELETE RESTRICT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='pos_order_items_order_id_fkey') THEN
    ALTER TABLE public.pos_order_items ADD CONSTRAINT pos_order_items_order_id_fkey
      FOREIGN KEY (order_id) REFERENCES public.pos_orders(id) ON DELETE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='pos_order_items_product_id_fkey') THEN
    ALTER TABLE public.pos_order_items ADD CONSTRAINT pos_order_items_product_id_fkey
      FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE SET NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='pos_sessions_company_id_fkey') THEN
    ALTER TABLE public.pos_sessions ADD CONSTRAINT pos_sessions_company_id_fkey
      FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='pos_sessions_register_id_fkey') THEN
    ALTER TABLE public.pos_sessions ADD CONSTRAINT pos_sessions_register_id_fkey
      FOREIGN KEY (register_id) REFERENCES public.cash_registers(id) ON DELETE RESTRICT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='cash_registers_company_id_fkey') THEN
    ALTER TABLE public.cash_registers ADD CONSTRAINT cash_registers_company_id_fkey
      FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
  END IF;

  -- expenses
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='expenses_company_id_fkey') THEN
    ALTER TABLE public.expenses ADD CONSTRAINT expenses_company_id_fkey
      FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='expenses_category_id_fkey') THEN
    ALTER TABLE public.expenses ADD CONSTRAINT expenses_category_id_fkey
      FOREIGN KEY (category_id) REFERENCES public.expense_categories(id) ON DELETE SET NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='expense_categories_company_id_fkey') THEN
    ALTER TABLE public.expense_categories ADD CONSTRAINT expense_categories_company_id_fkey
      FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
  END IF;

  -- accounting
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='accounts_company_id_fkey') THEN
    ALTER TABLE public.accounts ADD CONSTRAINT accounts_company_id_fkey
      FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='journal_entries_company_id_fkey') THEN
    ALTER TABLE public.journal_entries ADD CONSTRAINT journal_entries_company_id_fkey
      FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='journal_lines_entry_id_fkey') THEN
    ALTER TABLE public.journal_lines ADD CONSTRAINT journal_lines_entry_id_fkey
      FOREIGN KEY (entry_id) REFERENCES public.journal_entries(id) ON DELETE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='journal_lines_account_id_fkey') THEN
    ALTER TABLE public.journal_lines ADD CONSTRAINT journal_lines_account_id_fkey
      FOREIGN KEY (account_id) REFERENCES public.accounts(id) ON DELETE RESTRICT;
  END IF;

  -- company_members / company_settings
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='company_members_company_id_fkey') THEN
    ALTER TABLE public.company_members ADD CONSTRAINT company_members_company_id_fkey
      FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='company_settings_company_id_fkey') THEN
    ALTER TABLE public.company_settings ADD CONSTRAINT company_settings_company_id_fkey
      FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
  END IF;
END $$;

-- Indexes on FKs for performance
CREATE INDEX IF NOT EXISTS idx_sales_company ON public.sales(company_id);
CREATE INDEX IF NOT EXISTS idx_sales_customer ON public.sales(customer_id);
CREATE INDEX IF NOT EXISTS idx_sale_items_sale ON public.sale_items(sale_id);
CREATE INDEX IF NOT EXISTS idx_sale_items_product ON public.sale_items(product_id);
CREATE INDEX IF NOT EXISTS idx_payments_sale ON public.payments(sale_id);
CREATE INDEX IF NOT EXISTS idx_payments_customer ON public.payments(customer_id);
CREATE INDEX IF NOT EXISTS idx_payments_supplier ON public.payments(supplier_id);
CREATE INDEX IF NOT EXISTS idx_payments_purchase ON public.payments(purchase_id);
CREATE INDEX IF NOT EXISTS idx_stock_movements_product ON public.stock_movements(product_id);
CREATE INDEX IF NOT EXISTS idx_stock_movements_ref ON public.stock_movements(reference_type, reference_id);
CREATE INDEX IF NOT EXISTS idx_products_company ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_products_category ON public.products(category_id);
CREATE INDEX IF NOT EXISTS idx_purchase_items_purchase ON public.purchase_items(purchase_id);
CREATE INDEX IF NOT EXISTS idx_purchase_items_product ON public.purchase_items(product_id);
CREATE INDEX IF NOT EXISTS idx_pos_order_items_order ON public.pos_order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_pos_order_items_product ON public.pos_order_items(product_id);
CREATE INDEX IF NOT EXISTS idx_journal_lines_entry ON public.journal_lines(entry_id);
CREATE INDEX IF NOT EXISTS idx_journal_lines_account ON public.journal_lines(account_id);
CREATE INDEX IF NOT EXISTS idx_journal_entries_ref ON public.journal_entries(reference_type, reference_id);
