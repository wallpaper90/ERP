
-- 1) Drop duplicate JE triggers (same function fired twice on same table)
DROP TRIGGER IF EXISTS trg_je_expense ON public.expenses;
DROP TRIGGER IF EXISTS trg_je_purchase_return ON public.purchase_returns;
DROP TRIGGER IF EXISTS trg_je_sales_return ON public.sales_returns;

-- 2) Drop pos_orders JE trigger entirely.
-- POS orders are mirrored into the sales table, and sales already post their
-- own journal entry (cash/AR + revenue + tax). Posting again from pos_orders
-- double-counts revenue, cash, and tax in every accounting report.
DROP TRIGGER IF EXISTS trg_je_pos_order ON public.pos_orders;

-- 3) Clean up historical duplicate JEs created by the now-removed trigger.
DELETE FROM public.journal_entries
WHERE reference_type = 'pos_order';
