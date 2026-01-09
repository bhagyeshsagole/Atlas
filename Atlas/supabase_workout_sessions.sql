-- Workout session summaries for Supabase sync

-- 1) Table
create table if not exists public.workout_sessions (
  id uuid primary key,
  owner_id uuid not null references public.profiles(id) on delete cascade,
  routine_title text not null default '',
  started_at timestamptz null,
  ended_at timestamptz not null,
  day date not null,
  total_sets int not null default 0,
  total_reps int not null default 0,
  volume_kg double precision not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists workout_sessions_owner_day_idx
  on public.workout_sessions (owner_id, day desc);

-- 2) RLS
alter table public.workout_sessions enable row level security;
alter table public.workout_sessions force row level security;

drop policy if exists workout_sessions_select_self on public.workout_sessions;
create policy workout_sessions_select_self
  on public.workout_sessions
  for select
  using (owner_id = auth.uid());

drop policy if exists workout_sessions_insert_self on public.workout_sessions;
create policy workout_sessions_insert_self
  on public.workout_sessions
  for insert
  with check (owner_id = auth.uid());

drop policy if exists workout_sessions_update_self on public.workout_sessions;
create policy workout_sessions_update_self
  on public.workout_sessions
  for update
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

-- 3) RPC: upsert
create or replace function public.upsert_workout_session(
  session_id uuid,
  routine_title text,
  started_at timestamptz,
  ended_at timestamptz,
  total_sets int,
  total_reps int,
  volume_kg double precision
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'auth.uid() is required';
  end if;

  insert into public.workout_sessions as ws (
    id, owner_id, routine_title, started_at, ended_at, day, total_sets, total_reps, volume_kg
  ) values (
    session_id, uid, coalesce(routine_title, ''), started_at, ended_at, ended_at::date, coalesce(total_sets, 0), coalesce(total_reps, 0), coalesce(volume_kg, 0)
  )
  on conflict (id) do update set
    routine_title = excluded.routine_title,
    started_at = excluded.started_at,
    ended_at = excluded.ended_at,
    day = excluded.day,
    total_sets = excluded.total_sets,
    total_reps = excluded.total_reps,
    volume_kg = excluded.volume_kg,
    owner_id = uid,
    updated_at = now();
end;
$$;

revoke all on function public.upsert_workout_session(uuid, text, timestamptz, timestamptz, int, int, double precision) from public;
grant execute on function public.upsert_workout_session(uuid, text, timestamptz, timestamptz, int, int, double precision) to authenticated;

-- 4) Schema cache refresh
-- Run in SQL editor or dashboard: notify pgrst, 'reload schema';
