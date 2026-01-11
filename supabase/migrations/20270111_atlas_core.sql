-- Atlas core schema for Supabase: profiles, workouts (append-only), routines.
-- Safe to re-run: uses IF NOT EXISTS guards and additive policies.

-- Ensure pgcrypto for gen_random_uuid
create extension if not exists "pgcrypto";

-----------------------
-- profiles
-----------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'profiles' and policyname = 'profiles_select_self'
  ) then
    create policy "profiles_select_self" on public.profiles
      for select
      using (id = auth.uid());
  end if;
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'profiles' and policyname = 'profiles_insert_self'
  ) then
    create policy "profiles_insert_self" on public.profiles
      for insert
      with check (id = auth.uid());
  end if;
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'profiles' and policyname = 'profiles_update_self'
  ) then
    create policy "profiles_update_self" on public.profiles
      for update
      using (id = auth.uid())
      with check (id = auth.uid());
  end if;
end$$;

-----------------------
-- workout_sessions (append-only)
-----------------------
create table if not exists public.workout_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  local_id text not null,
  started_at timestamptz,
  ended_at timestamptz,
  routine_local_id text,
  routine_title text,
  total_sets int not null default 0,
  total_reps int not null default 0,
  total_volume_kg double precision not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(user_id, local_id)
);
create index if not exists idx_workout_sessions_user_ended_at on public.workout_sessions(user_id, ended_at desc);
create index if not exists idx_workout_sessions_user_updated_at on public.workout_sessions(user_id, updated_at desc);

alter table public.workout_sessions enable row level security;

do $$
begin
  if not exists (select 1 from pg_policies where policyname='ws_select_owner' and tablename='workout_sessions') then
    create policy "ws_select_owner" on public.workout_sessions for select using (user_id = auth.uid());
  end if;
  if not exists (select 1 from pg_policies where policyname='ws_insert_owner' and tablename='workout_sessions') then
    create policy "ws_insert_owner" on public.workout_sessions for insert with check (user_id = auth.uid());
  end if;
  if not exists (select 1 from pg_policies where policyname='ws_update_owner' and tablename='workout_sessions') then
    create policy "ws_update_owner" on public.workout_sessions for update using (user_id = auth.uid()) with check (user_id = auth.uid());
  end if;
end$$;

-- Optional append-only safety: forbid deletes explicitly
drop rule if exists workout_sessions_no_delete on public.workout_sessions;
create rule workout_sessions_no_delete as on delete to public.workout_sessions do instead nothing;

-----------------------
-- session_exercises
-----------------------
create table if not exists public.session_exercises (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  session_id uuid not null references public.workout_sessions(id) on delete cascade,
  local_id text not null,
  exercise_name text not null,
  sort_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(user_id, local_id)
);
create index if not exists idx_session_exercises_session_sort on public.session_exercises(session_id, sort_order);

alter table public.session_exercises enable row level security;

do $$
begin
  if not exists (select 1 from pg_policies where policyname='se_select_owner' and tablename='session_exercises') then
    create policy "se_select_owner" on public.session_exercises for select using (user_id = auth.uid());
  end if;
  if not exists (select 1 from pg_policies where policyname='se_insert_owner' and tablename='session_exercises') then
    create policy "se_insert_owner" on public.session_exercises for insert with check (user_id = auth.uid());
  end if;
  if not exists (select 1 from pg_policies where policyname='se_update_owner' and tablename='session_exercises') then
    create policy "se_update_owner" on public.session_exercises for update using (user_id = auth.uid()) with check (user_id = auth.uid());
  end if;
end$$;

drop rule if exists session_exercises_no_delete on public.session_exercises;
create rule session_exercises_no_delete as on delete to public.session_exercises do instead nothing;

-----------------------
-- set_logs
-----------------------
create table if not exists public.set_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  session_exercise_id uuid not null references public.session_exercises(id) on delete cascade,
  local_id text not null,
  performed_at timestamptz not null default now(),
  weight_kg double precision not null,
  reps int not null,
  entered_unit text null,
  tag text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(user_id, local_id)
);
create index if not exists idx_set_logs_exercise_time on public.set_logs(session_exercise_id, performed_at);

alter table public.set_logs enable row level security;

do $$
begin
  if not exists (select 1 from pg_policies where policyname='sl_select_owner' and tablename='set_logs') then
    create policy "sl_select_owner" on public.set_logs for select using (user_id = auth.uid());
  end if;
  if not exists (select 1 from pg_policies where policyname='sl_insert_owner' and tablename='set_logs') then
    create policy "sl_insert_owner" on public.set_logs for insert with check (user_id = auth.uid());
  end if;
  if not exists (select 1 from pg_policies where policyname='sl_update_owner' and tablename='set_logs') then
    create policy "sl_update_owner" on public.set_logs for update using (user_id = auth.uid()) with check (user_id = auth.uid());
  end if;
end$$;

drop rule if exists set_logs_no_delete on public.set_logs;
create rule set_logs_no_delete as on delete to public.set_logs do instead nothing;

-----------------------
-- routines (soft deletable)
-----------------------
create table if not exists public.routines (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  local_id text not null,
  group_id text not null,
  title text not null,
  is_coach_suggested boolean not null default false,
  deleted_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(user_id, local_id)
);
create index if not exists idx_routines_user_updated_at on public.routines(user_id, updated_at desc);
create index if not exists idx_routines_user_group on public.routines(user_id, group_id);

alter table public.routines enable row level security;

do $$
begin
  if not exists (select 1 from pg_policies where policyname='routines_select_owner' and tablename='routines') then
    create policy "routines_select_owner" on public.routines for select using (user_id = auth.uid());
  end if;
  if not exists (select 1 from pg_policies where policyname='routines_insert_owner' and tablename='routines') then
    create policy "routines_insert_owner" on public.routines for insert with check (user_id = auth.uid());
  end if;
  if not exists (select 1 from pg_policies where policyname='routines_update_owner' and tablename='routines') then
    create policy "routines_update_owner" on public.routines for update using (user_id = auth.uid()) with check (user_id = auth.uid());
  end if;
  if not exists (select 1 from pg_policies where policyname='routines_delete_owner' and tablename='routines') then
    create policy "routines_delete_owner" on public.routines for delete using (user_id = auth.uid());
  end if;
end$$;

-----------------------
-- routine_exercises
-----------------------
create table if not exists public.routine_exercises (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  routine_id uuid not null references public.routines(id) on delete cascade,
  local_id text not null,
  exercise_name text not null,
  sort_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(user_id, local_id)
);
create index if not exists idx_routine_exercises_routine_sort on public.routine_exercises(routine_id, sort_order);

alter table public.routine_exercises enable row level security;

do $$
begin
  if not exists (select 1 from pg_policies where policyname='re_select_owner' and tablename='routine_exercises') then
    create policy "re_select_owner" on public.routine_exercises for select using (user_id = auth.uid());
  end if;
  if not exists (select 1 from pg_policies where policyname='re_insert_owner' and tablename='routine_exercises') then
    create policy "re_insert_owner" on public.routine_exercises for insert with check (user_id = auth.uid());
  end if;
  if not exists (select 1 from pg_policies where policyname='re_update_owner' and tablename='routine_exercises') then
    create policy "re_update_owner" on public.routine_exercises for update using (user_id = auth.uid()) with check (user_id = auth.uid());
  end if;
  if not exists (select 1 from pg_policies where policyname='re_delete_owner' and tablename='routine_exercises') then
    create policy "re_delete_owner" on public.routine_exercises for delete using (user_id = auth.uid());
  end if;
end$$;

-----------------------
-- updated_at trigger helper
-----------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_workout_sessions_updated_at on public.workout_sessions;
create trigger trg_workout_sessions_updated_at
before update on public.workout_sessions
for each row execute function public.set_updated_at();

drop trigger if exists trg_session_exercises_updated_at on public.session_exercises;
create trigger trg_session_exercises_updated_at
before update on public.session_exercises
for each row execute function public.set_updated_at();

drop trigger if exists trg_set_logs_updated_at on public.set_logs;
create trigger trg_set_logs_updated_at
before update on public.set_logs
for each row execute function public.set_updated_at();

drop trigger if exists trg_routines_updated_at on public.routines;
create trigger trg_routines_updated_at
before update on public.routines
for each row execute function public.set_updated_at();

drop trigger if exists trg_routine_exercises_updated_at on public.routine_exercises;
create trigger trg_routine_exercises_updated_at
before update on public.routine_exercises
for each row execute function public.set_updated_at();

