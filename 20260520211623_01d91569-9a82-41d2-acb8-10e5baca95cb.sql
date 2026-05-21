-- Add missing foreign keys so PostgREST nested selects (customer:customers(...), etc.) work reliably.
-- Each FK is added only if it does not already exist.

DO $$
DECLARE
  rec record;
BEGIN
  FOR rec IN
    SELECT * FROM (VALUES
      -- sales
      ('sales', 'sales_company_id_fkey', 'company_id', 'companies', 'id', 'CASCADE'),
      ('sales', 'sales_customer_id_fkey', 'customer_id', 'customers', 'id', 'SET NULL'),
      -- sale_items
      ('sale_items', 'sale_items_sale_id_fkey', 'sale_id', 'sales', 'id', 'CASCADE'),
      ('sale_items', 'sale_items_product_id_fkey', 'product_id', 'products', 'id', 'SET NULL'),
      -- purchases
      ('purchases', 'purchases_company_id_fkey', 'company_id', 'companies', 'id', 'CASCADE'),
      ('purchases', 'purchases_supplier_id_fkey', 'supplier_id', 'suppliers', 'id', 'SET NULL'),
      -- purchase_items
      ('purchase_items', 'purchase_items_purchase_id_fkey', 'purchase_id', 'purchases', 'id', 'CASCADE'),
      ('purchase_items', 'purchase_items_product_id_fkey', 'product_id', 'products', 'id', 'SET NULL'),
      -- payments
      ('payments', 'payments_company_id_fkey', 'company_id', 'companies', 'id', 'CASCADE'),
      ('payments', 'payments_customer_id_fkey', 'customer_id', 'customers', 'id', 'SET NULL'),
      ('payments', 'payments_supplier_id_fkey', 'supplier_id', 'suppliers', 'id', 'SET NULL'),
      ('payments', 'payments_sale_id_fkey', 'sale_id', 'sales', 'id', 'SET NULL'),
      ('payments', 'payments_purchase_id_fkey', 'purchase_id', 'purchases', 'id', 'SET NULL'),
      -- sales_returns
      ('sales_returns', 'sales_returns_company_id_fkey', 'company_id', 'companies', 'id', 'CASCADE'),
      ('sales_returns', 'sales_returns_sale_id_fkey', 'sale_id', 'sales', 'id', 'CASCADE'),
      ('sales_returns', 'sales_returns_customer_id_fkey', 'customer_id', 'customers', 'id', 'SET NULL'),
      ('sales_return_items', 'sales_return_items_return_id_fkey', 'return_id', 'sales_returns', 'id', 'CASCADE'),
      ('sales_return_items', 'sales_return_items_product_id_fkey', 'product_id', 'products', 'id', 'SET NULL'),
      -- purchase_returns
      ('purchase_returns', 'purchase_returns_company_id_fkey', 'company_id', 'companies', 'id', 'CASCADE'),
      ('purchase_returns', 'purchase_returns_purchase_id_fkey', 'purchase_id', 'purchases', 'id', 'CASCADE'),
      ('purchase_returns', 'purchase_returns_supplier_id_fkey', 'supplier_id', 'suppliers', 'id', 'SET NULL'),
      ('purchase_return_items', 'purchase_return_items_return_id_fkey', 'return_id', 'purchase_returns', 'id', 'CASCADE'),
      ('purchase_return_items', 'purchase_return_items_product_id_fkey', 'product_id', 'products', 'id', 'SET NULL'),
      -- expenses
      ('expenses', 'expenses_company_id_fkey', 'company_id', 'companies', 'id', 'CASCADE'),
      ('expenses', 'expenses_category_id_fkey', 'category_id', 'expense_categories', 'id', 'SET NULL'),
      ('expenses', 'expenses_cost_center_id_fkey', 'cost_center_id', 'cost_centers', 'id', 'SET NULL'),
      -- products / customers / suppliers / categories
      ('products', 'products_company_id_fkey', 'company_id', 'companies', 'id', 'CASCADE'),
      ('products', 'products_category_id_fkey', 'category_id', 'categories', 'id', 'SET NULL'),
      ('customers', 'customers_company_id_fkey', 'company_id', 'companies', 'id', 'CASCADE'),
      ('suppliers', 'suppliers_company_id_fkey', 'company_id', 'companies', 'id', 'CASCADE'),
      ('categories', 'categories_company_id_fkey', 'company_id', 'companies', 'id', 'CASCADE'),
      ('expense_categories', 'expense_categories_company_id_fkey', 'company_id', 'companies', 'id', 'CASCADE'),
      -- stock_movements
      ('stock_movements', 'stock_movements_company_id_fkey', 'company_id', 'companies', 'id', 'CASCADE'),
      ('stock_movements', 'stock_movements_product_id_fkey', 'product_id', 'products', 'id', 'CASCADE'),
      -- accounting
      ('accounts', 'accounts_company_id_fkey', 'company_id', 'companies', 'id', 'CASCADE'),
      ('accounts', 'accounts_parent_id_fkey', 'parent_id', 'accounts', 'id', 'SET NULL'),
      ('journal_entries', 'journal_entries_company_id_fkey', 'company_id', 'companies', 'id', 'CASCADE'),
      ('journal_lines', 'journal_lines_entry_id_fkey', 'entry_id', 'journal_entries', 'id', 'CASCADE'),
      ('journal_lines', 'journal_lines_account_id_fkey', 'account_id', 'accounts', 'id', 'RESTRICT'),
      ('journal_lines', 'journal_lines_cost_center_id_fkey', 'cost_center_id', 'cost_centers', 'id', 'SET NULL'),
      -- pos
      ('pos_orders', 'pos_orders_company_id_fkey', 'company_id', 'companies', 'id', 'CASCADE'),
      ('pos_orders', 'pos_orders_customer_id_fkey', 'customer_id', 'customers', 'id', 'SET NULL'),
      ('pos_orders', 'pos_orders_session_id_fkey', 'session_id', 'pos_sessions', 'id', 'CASCADE'),
      ('pos_order_items', 'pos_order_items_order_id_fkey', 'order_id', 'pos_orders', 'id', 'CASCADE'),
      ('pos_order_items', 'pos_order_items_product_id_fkey', 'product_id', 'products', 'id', 'SET NULL'),
      ('pos_sessions', 'pos_sessions_company_id_fkey', 'company_id', 'companies', 'id', 'CASCADE'),
      ('pos_sessions', 'pos_sessions_register_id_fkey', 'register_id', 'cash_registers', 'id', 'CASCADE'),
      ('cash_registers', 'cash_registers_company_id_fkey', 'company_id', 'companies', 'id', 'CASCADE'),
      -- audit
      ('audit_logs', 'audit_logs_company_id_fkey', 'company_id', 'companies', 'id', 'CASCADE'),
      -- notifications
      ('notifications', 'notifications_company_id_fkey', 'company_id', 'companies', 'id', 'CASCADE'),
      -- company_settings / members / subscriptions
      ('company_settings', 'company_settings_company_id_fkey', 'company_id', 'companies', 'id', 'CASCADE'),
      ('company_members', 'company_members_company_id_fkey', 'company_id', 'companies', 'id', 'CASCADE'),
      ('subscriptions', 'subscriptions_company_id_fkey', 'company_id', 'companies', 'id', 'CASCADE'),
      -- cost centers / budgets / fiscal
      ('cost_centers', 'cost_centers_company_id_fkey', 'company_id', 'companies', 'id', 'CASCADE'),
      ('cost_centers', 'cost_centers_parent_id_fkey', 'parent_id', 'cost_centers', 'id', 'SET NULL'),
      ('budgets', 'budgets_company_id_fkey', 'company_id', 'companies', 'id', 'CASCADE'),
      ('budget_lines', 'budget_lines_budget_id_fkey', 'budget_id', 'budgets', 'id', 'CASCADE'),
      ('budget_lines', 'budget_lines_account_id_fkey', 'account_id', 'accounts', 'id', 'CASCADE'),
      ('budget_lines', 'budget_lines_cost_center_id_fkey', 'cost_center_id', 'cost_centers', 'id', 'SET NULL'),
      ('fiscal_periods', 'fiscal_periods_company_id_fkey', 'company_id', 'companies', 'id', 'CASCADE')
    ) AS t(tbl, cname, col, ref_tbl, ref_col, on_del)
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_constraint c
      JOIN pg_class cl ON cl.oid = c.conrelid
      JOIN pg_namespace n ON n.oid = cl.relnamespace
      WHERE n.nspname = 'public' AND cl.relname = rec.tbl AND c.conname = rec.cname
    ) THEN
      EXECUTE format(
        'ALTER TABLE public.%I ADD CONSTRAINT %I FOREIGN KEY (%I) REFERENCES public.%I(%I) ON DELETE %s',
        rec.tbl, rec.cname, rec.col, rec.ref_tbl, rec.ref_col, rec.on_del
      );
    END IF;
  END LOOP;
END $$;

-- Helpful indexes on FK columns (skip if exists)
CREATE INDEX IF NOT EXISTS idx_sales_customer ON public.sales(customer_id);
CREATE INDEX IF NOT EXISTS idx_sales_company_date ON public.sales(company_id, invoice_date DESC);
CREATE INDEX IF NOT EXISTS idx_sale_items_sale ON public.sale_items(sale_id);
CREATE INDEX IF NOT EXISTS idx_purchases_supplier ON public.purchases(supplier_id);
CREATE INDEX IF NOT EXISTS idx_purchases_company_date ON public.purchases(company_id, invoice_date DESC);
CREATE INDEX IF NOT EXISTS idx_purchase_items_purchase ON public.purchase_items(purchase_id);
CREATE INDEX IF NOT EXISTS idx_payments_customer ON public.payments(customer_id);
CREATE INDEX IF NOT EXISTS idx_payments_supplier ON public.payments(supplier_id);
CREATE INDEX IF NOT EXISTS idx_payments_sale ON public.payments(sale_id);
CREATE INDEX IF NOT EXISTS idx_payments_purchase ON public.payments(purchase_id);
CREATE INDEX IF NOT EXISTS idx_expenses_company_date ON public.expenses(company_id, expense_date DESC);
CREATE INDEX IF NOT EXISTS idx_journal_entries_company_date ON public.journal_entries(company_id, entry_date DESC);
CREATE INDEX IF NOT EXISTS idx_journal_lines_entry ON public.journal_lines(entry_id);
CREATE INDEX IF NOT EXISTS idx_journal_lines_account ON public.journal_lines(account_id);
