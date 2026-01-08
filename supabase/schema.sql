-- Supabase profiles schema and RLS for Atlas.

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text,
  created_at timestamptz default now()
);

-- Enforce unique email (case-insensitive) when present.
create unique index if not exists profiles_email_unique on public.profiles (lower(email));

alter table public.profiles enable row level security;

-- Users can read their own profile.
create policy if not exists "Profiles select own" on public.profiles
for select using (auth.uid() = id);

-- Users can update their own profile.
create policy if not exists "Profiles update own" on public.profiles
for update using (auth.uid() = id)
with check (auth.uid() = id);

-- Users can insert their own profile row.
create policy if not exists "Profiles insert own" on public.profiles
for insert with check (auth.uid() = id);
