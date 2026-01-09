-- Supabase profiles schema and RLS for Atlas.
-- Apply this in the Supabase SQL editor or via migrations.

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text,
  display_name text null,
  avatar_url text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_email_lowercase check (email is null or email = lower(email))
);

-- Enforce unique email (case-insensitive) when present.
create unique index if not exists profiles_email_unique on public.profiles (lower(email));

-- Normalize any existing mixed-case emails to satisfy the constraint/index.
update public.profiles
set email = lower(trim(email))
where email is not null and email <> lower(trim(email));

alter table public.profiles enable row level security;
alter table public.profiles force row level security;

-- Users can read their own profile.
drop policy if exists "Profiles select own" on public.profiles;
create policy "Profiles select own" on public.profiles
for select using (auth.uid() = id);

-- Users can update their own profile.
drop policy if exists "Profiles update own" on public.profiles;
create policy "Profiles update own" on public.profiles
for update using (auth.uid() = id)
with check (auth.uid() = id);

-- Users can insert their own profile row.
drop policy if exists "Profiles insert own" on public.profiles;
create policy "Profiles insert own" on public.profiles
for insert with check (auth.uid() = id);

-- Maintain updated_at automatically on updates.
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
for each row
execute function public.set_profile_updated_at();

-- Normalize email to lowercase on write.
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

-- Trigger to auto-create profiles for new auth users.
create or replace function public.create_profile_for_new_user()
returns trigger
language plpgsql
security definer
as $$
begin
  insert into public.profiles (id, email)
  values (new.id, new.email)
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.create_profile_for_new_user();
