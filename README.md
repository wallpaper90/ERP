# SaaS Arabi — نسخة Vercel

تطبيق TanStack Start جاهز للنشر على Vercel بدون أي تعديل.

## المتطلبات
- Node.js 20+
- حساب Vercel + حساب Supabase

## التشغيل محلياً
```bash
npm install
cp .env.example .env
# عبئ القيم في .env
npm run dev
```

## النشر على Vercel
1. ارفع المجلد إلى GitHub.
2. في Vercel: **New Project** → اختر المستودع.
3. اترك Framework Preset على **Other** (vercel.json يعالج الإعدادات).
4. أضف متغيرات البيئة (نفس محتوى `.env.example`) في **Settings → Environment Variables**:
   - `VITE_SUPABASE_URL`
   - `VITE_SUPABASE_PUBLISHABLE_KEY`
   - `VITE_SUPABASE_PROJECT_ID`
   - `SUPABASE_URL`
   - `SUPABASE_PUBLISHABLE_KEY`
   - `SUPABASE_SERVICE_ROLE_KEY`
5. اضغط **Deploy**.

## ملاحظات
- قاعدة البيانات وإعداداتها على Supabase موجودة في مجلد `supabase/`. شغّل المايجريشن من Supabase Studio أو CLI إذا أردت بناء قاعدة بيانات جديدة.
- نقطة الدخول لـ Vercel يبنيها TanStack Start تلقائياً عبر `target: "vercel"` في `vite.config.ts` (مخرج `.vercel/output`).
