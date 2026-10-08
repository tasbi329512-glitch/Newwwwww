# SASHA Commerce — Phase 1: Foundation

Next.js 15 + TypeScript + Tailwind + Supabase. Deploys on Vercel.

## What is in Phase 1
- Auth (email/password), profiles
- Multi-tenant stores with owner/admin/staff roles, enforced by Postgres RLS
- Plans, feature flags, entitlements (override > plan > default)
- Versioned API: `/api/2026-04/health`, `/api/2026-04/stores`
- Merchant dashboard (`/admin`), Super Admin (`/superadmin`)
- Append-only audit log

## Setup
1. Create a Supabase project. Run `supabase/migrations/0001_foundation.sql` in the SQL Editor.
2. Copy `.env.example` to `.env.local` and fill in the keys.
3. `npm install && npm run dev`
4. Sign up, then make yourself super admin (SQL at the bottom of the migration).

## Deploy on Vercel
1. Push to GitHub, import the repo in Vercel.
2. Add the 3 env vars from `.env.example` in Project Settings.
3. In Supabase > Auth > URL Configuration, add your Vercel URL as Site URL.
4. For quick testing, turn off "Confirm email" in Supabase Auth > Providers > Email.
