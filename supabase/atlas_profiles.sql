-- Supabase profiles table + RLS for Atlas.
-- Run this in the Supabase SQL editor (or a migration) before shipping auth.

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text,
  display_name text,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_email_lowercase check (email is null or email = lower(email))
);

create unique index if not exists profiles_email_unique on public.profiles (lower(email));

-- Normalize any existing mixed-case emails so the constraint stays valid.
update public.profiles
set email = lower(trim(email))
where email is not null and email <> lower(trim(email));

-- Keep updated_at in sync on updates.
create or replace function public.set_profile_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_profile_updated_at();

-- Normalize email to lowercase on insert/update so RLS upserts never fail the check.
create or replace function public._profiles_email_lowercase()
returns trigger
language plpgsql
as $$
begin
  if new.email is not null then
    new.email := lower(trim(new.email));
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_email_lowercase_trg on public.profiles;
create trigger profiles_email_lowercase_trg
before insert or update on public.profiles
for each row
execute function public._profiles_email_lowercase();

-- Enforce RLS so users only see/manage their own profile.
alter table public.profiles enable row level security;
alter table public.profiles force row level security;

drop policy if exists profiles_select_self on public.profiles;
create policy profiles_select_self on public.profiles
for select using (auth.uid() = id);

drop policy if exists profiles_insert_self on public.profiles;
create policy profiles_insert_self on public.profiles
for insert with check (auth.uid() = id);

drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles
for update using (auth.uid() = id) with check (auth.uid() = id);
