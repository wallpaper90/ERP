-- Sales
CREATE INDEX IF NOT EXISTS idx_sales_company_date ON public.sales (company_id, invoice_date DESC) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_sales_company_status ON public.sales (company_id, status) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_sales_company_customer ON public.sales (company_id, customer_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_sales_company_invoice_number ON public.sales (company_id, invoice_number);
CREATE INDEX IF NOT EXISTS idx_sales_company_due_date ON public.sales (company_id, due_date) WHERE deleted_at IS NULL AND status <> 'paid';
CREATE INDEX IF NOT EXISTS idx_sale_items_sale ON public.sale_items (sale_id);
CREATE INDEX IF NOT EXISTS idx_sale_items_product ON public.sale_items (product_id);

-- Purchases
CREATE INDEX IF NOT EXISTS idx_purchases_company_date ON public.purchases (company_id, invoice_date DESC) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_purchases_company_status ON public.purchases (company_id, status) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_purchases_company_supplier ON public.purchases (company_id, supplier_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_purchase_items_purchase ON public.purchase_items (purchase_id);
CREATE INDEX IF NOT EXISTS idx_purchase_items_product ON public.purchase_items (product_id);

-- Payments
CREATE INDEX IF NOT EXISTS idx_payments_company_date ON public.payments (company_id, payment_date DESC) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_payments_sale ON public.payments (sale_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_payments_purchase ON public.payments (purchase_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_payments_company_customer ON public.payments (company_id, customer_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_payments_company_supplier ON public.payments (company_id, supplier_id) WHERE deleted_at IS NULL;

-- Customers / Suppliers
CREATE INDEX IF NOT EXISTS idx_customers_company_name ON public.customers (company_id, name) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_suppliers_company_name ON public.suppliers (company_id, name) WHERE deleted_at IS NULL;

-- Products
CREATE INDEX IF NOT EXISTS idx_products_company_active ON public.products (company_id, is_active) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_products_company_name ON public.products (company_id, name) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_products_company_sku ON public.products (company_id, sku) WHERE sku IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_products_low_stock ON public.products (company_id) WHERE deleted_at IS NULL AND stock_qty <= min_stock;

-- Expenses
CREATE INDEX IF NOT EXISTS idx_expenses_company_date ON public.expenses (company_id, expense_date DESC) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_expenses_company_category ON public.expenses (company_id, category_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_expense_categories_company ON public.expense_categories (company_id);

-- Stock movements
CREATE INDEX IF NOT EXISTS idx_stock_movements_company_date ON public.stock_movements (company_id, created_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_stock_movements_product ON public.stock_movements (product_id, created_at DESC) WHERE deleted_at IS NULL;

-- Notifications
CREATE INDEX IF NOT EXISTS idx_notifications_company_user_created ON public.notifications (company_id, user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_unread ON public.notifications (company_id, user_id) WHERE is_read = false;

-- Audit / Members / Subscriptions
CREATE INDEX IF NOT EXISTS idx_audit_logs_company_created ON public.audit_logs (company_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_entity ON public.audit_logs (company_id, entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_company_members_user ON public.company_members (user_id);
CREATE INDEX IF NOT EXISTS idx_company_members_company ON public.company_members (company_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_company ON public.subscriptions (company_id);

-- Update planner statistics
ANALYZE public.sales;
ANALYZE public.sale_items;
ANALYZE public.purchases;
ANALYZE public.purchase_items;
ANALYZE public.payments;
ANALYZE public.products;
ANALYZE public.customers;
ANALYZE public.suppliers;
ANALYZE public.expenses;
ANALYZE public.stock_movements;
ANALYZE public.notifications;