-- Create routines and routine_exercises with owner-only RLS
create extension if not exists pgcrypto;

create table if not exists public.routines (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  is_coach_suggested boolean not null default false,
  coach_name text null,
  tags text[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.routine_exercises (
  id uuid primary key default gen_random_uuid(),
  routine_id uuid not null references public.routines(id) on delete cascade,
  position int not null,
  name text not null,
  created_at timestamptz not null default now()
);

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists routines_set_updated_at on public.routines;
create trigger routines_set_updated_at
before update on public.routines
for each row execute function public.set_updated_at();

alter table public.routines enable row level security;
alter table public.routine_exercises enable row level security;

drop policy if exists routines_select_own on public.routines;
create policy routines_select_own on public.routines
for select using (owner_user_id = auth.uid());

drop policy if exists routines_insert_own on public.routines;
create policy routines_insert_own on public.routines
for insert with check (owner_user_id = auth.uid());

drop policy if exists routines_update_own on public.routines;
create policy routines_update_own on public.routines
for update using (owner_user_id = auth.uid());

drop policy if exists routines_delete_own on public.routines;
create policy routines_delete_own on public.routines
for delete using (owner_user_id = auth.uid());

drop policy if exists routine_exercises_select_own on public.routine_exercises;
create policy routine_exercises_select_own on public.routine_exercises
for select using (
  exists (
    select 1 from public.routines r
    where r.id = routine_exercises.routine_id
      and r.owner_user_id = auth.uid()
  )
);

drop policy if exists routine_exercises_insert_own on public.routine_exercises;
create policy routine_exercises_insert_own on public.routine_exercises
for insert with check (
  exists (
    select 1 from public.routines r
    where r.id = routine_exercises.routine_id
      and r.owner_user_id = auth.uid()
  )
);

drop policy if exists routine_exercises_update_own on public.routine_exercises;
create policy routine_exercises_update_own on public.routine_exercises
for update using (
  exists (
    select 1 from public.routines r
    where r.id = routine_exercises.routine_id
      and r.owner_user_id = auth.uid()
  )
);

drop policy if exists routine_exercises_delete_own on public.routine_exercises;
create policy routine_exercises_delete_own on public.routine_exercises
for delete using (
  exists (
    select 1 from public.routines r
    where r.id = routine_exercises.routine_id
      and r.owner_user_id = auth.uid()
  )
);

select pg_notify('pgrst', 'reload schema');
