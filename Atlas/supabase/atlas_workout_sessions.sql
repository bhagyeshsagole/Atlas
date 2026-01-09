-- Atlas workout session cloud sync (table + RLS + RPC)

-- 1) Table
create table if not exists public.workout_sessions (
  id uuid primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  routine_title text not null,
  started_at timestamptz null,
  ended_at timestamptz not null,
  total_sets int not null default 0,
  total_reps int not null default 0,
  volume_kg double precision not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Ensure per-user uniqueness for the same session id
create unique index if not exists workout_sessions_user_id_id_idx
  on public.workout_sessions (user_id, id);

create index if not exists workout_sessions_user_ended_idx
  on public.workout_sessions (user_id, ended_at desc);

-- updated_at trigger
create or replace function public._workout_sessions_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists workout_sessions_updated_at_trg on public.workout_sessions;
create trigger workout_sessions_updated_at_trg
before update on public.workout_sessions
for each row execute function public._workout_sessions_set_updated_at();

-- 2) RLS
alter table public.workout_sessions enable row level security;
alter table public.workout_sessions force row level security;

drop policy if exists workout_sessions_select_self on public.workout_sessions;
create policy workout_sessions_select_self
  on public.workout_sessions
  for select
  using (user_id = auth.uid());

drop policy if exists workout_sessions_insert_self on public.workout_sessions;
create policy workout_sessions_insert_self
  on public.workout_sessions
  for insert
  with check (user_id = auth.uid());

drop policy if exists workout_sessions_update_self on public.workout_sessions;
create policy workout_sessions_update_self
  on public.workout_sessions
  for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists workout_sessions_delete_self on public.workout_sessions;
create policy workout_sessions_delete_self
  on public.workout_sessions
  for delete
  using (user_id = auth.uid());

-- 3) RPC: upsert_workout_session (self only)
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
security invoker
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'auth.uid() is required';
  end if;

  insert into public.workout_sessions (
    id, user_id, routine_title, started_at, ended_at, total_sets, total_reps, volume_kg, updated_at
  ) values (
    session_id, uid, coalesce(routine_title, ''), started_at, ended_at,
    coalesce(total_sets, 0), coalesce(total_reps, 0), coalesce(volume_kg, 0), now()
  )
  on conflict (id) do update set
    user_id     = uid,
    routine_title = excluded.routine_title,
    started_at  = excluded.started_at,
    ended_at    = excluded.ended_at,
    total_sets  = excluded.total_sets,
    total_reps  = excluded.total_reps,
    volume_kg   = excluded.volume_kg,
    updated_at  = now();
end;
$$;

revoke all on function public.upsert_workout_session(uuid,text,timestamptz,timestamptz,int,int,double precision) from public;
grant execute on function public.upsert_workout_session(uuid,text,timestamptz,timestamptz,int,int,double precision) to authenticated;

-- 4) Friend history RPCs (self-only for now)
create or replace function public.list_workout_sessions_for_user(
  target_user_id uuid,
  from_ts timestamptz default null,
  to_ts timestamptz default null,
  limit_count int default 60
)
returns table (
  session_id uuid,
  routine_title text,
  started_at text,
  ended_at text,
  total_sets int,
  total_reps int,
  volume_kg double precision
)
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

  if target_user_id <> uid then
    raise exception 'Not authorized';
  end if;

  return query
  select
    w.id as session_id,
    w.routine_title,
    to_char(w.started_at, 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') as started_at,
    to_char(w.ended_at, 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') as ended_at,
    w.total_sets,
    w.total_reps,
    w.volume_kg
  from public.workout_sessions w
  where w.user_id = target_user_id
    and (from_ts is null or w.ended_at >= from_ts)
    and (to_ts is null or w.ended_at <= to_ts)
  order by w.ended_at desc
  limit greatest(1, least(limit_count, 200));
end;
$$;

revoke all on function public.list_workout_sessions_for_user(uuid,timestamptz,timestamptz,int) from public;
grant execute on function public.list_workout_sessions_for_user(uuid,timestamptz,timestamptz,int) to authenticated;

create or replace function public.workout_stats_for_user_row(target_user_id uuid)
returns table (
  sessions_total int,
  best_volume_kg double precision,
  best_total_reps int,
  best_total_sets int,
  latest_ended_at text,
  longest_duration_seconds double precision
)
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

  if target_user_id <> uid then
    raise exception 'Not authorized';
  end if;

  return query
  select
    count(*)::int as sessions_total,
    coalesce(max(volume_kg), 0) as best_volume_kg,
    coalesce(max(total_reps), 0) as best_total_reps,
    coalesce(max(total_sets), 0) as best_total_sets,
    to_char(max(ended_at), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') as latest_ended_at,
    coalesce(max(extract(epoch from (ended_at - started_at))), 0) as longest_duration_seconds
  from public.workout_sessions
  where user_id = target_user_id;
end;
$$;

revoke all on function public.workout_stats_for_user_row(uuid) from public;
grant execute on function public.workout_stats_for_user_row(uuid) to authenticated;

-- 5) Table permissions
revoke all on public.workout_sessions from anon, authenticated, public;
grant select, insert, update, delete on public.workout_sessions to authenticated;

-- 6) Schema cache reload (run after applying if needed)
-- notify pgrst, 'reload schema';
