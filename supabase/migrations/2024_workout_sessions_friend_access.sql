-- Workout sessions (owner + friends read)

create table if not exists public.workout_sessions (
  session_id uuid primary key,
  user_id uuid not null references auth.users(id),
  routine_title text not null default '',
  started_at timestamptz null,
  ended_at timestamptz not null,
  total_sets int not null default 0,
  total_reps int not null default 0,
  volume_kg numeric not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists workout_sessions_user_ended_idx
  on public.workout_sessions (user_id, ended_at desc);

create or replace function public._ws_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists ws_updated_at_trg on public.workout_sessions;
create trigger ws_updated_at_trg
before update on public.workout_sessions
for each row execute function public._ws_set_updated_at();

alter table public.workout_sessions enable row level security;
alter table public.workout_sessions force row level security;

drop policy if exists ws_owner_select on public.workout_sessions;
create policy ws_owner_select
  on public.workout_sessions
  for select
  using (user_id = auth.uid());

drop policy if exists ws_owner_insert on public.workout_sessions;
create policy ws_owner_insert
  on public.workout_sessions
  for insert
  with check (user_id = auth.uid());

drop policy if exists ws_owner_update on public.workout_sessions;
create policy ws_owner_update
  on public.workout_sessions
  for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists ws_owner_delete on public.workout_sessions;
create policy ws_owner_delete
  on public.workout_sessions
  for delete
  using (user_id = auth.uid());

drop policy if exists ws_friends_select on public.workout_sessions;
create policy ws_friends_select
  on public.workout_sessions
  for select
  using (
    exists (
      select 1 from public.friends f
      where (f.user_a = auth.uid() and f.user_b = workout_sessions.user_id)
         or (f.user_b = auth.uid() and f.user_a = workout_sessions.user_id)
    )
  );

create or replace function public.are_friends(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.friends f
    where f.user_a = least(a,b)
      and f.user_b = greatest(a,b)
  );
$$;

revoke all on function public.are_friends(uuid,uuid) from public;
grant execute on function public.are_friends(uuid,uuid) to authenticated;

create or replace function public.upsert_workout_session(
  session_id uuid,
  routine_title text,
  started_at timestamptz,
  ended_at timestamptz,
  total_sets int,
  total_reps int,
  volume_kg numeric
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  owner_id uuid;
begin
  if uid is null then
    raise exception 'auth.uid() is required';
  end if;

  select user_id into owner_id from public.workout_sessions where session_id = session_id;
  if owner_id is not null and owner_id <> uid then
    raise exception 'session owned by another user';
  end if;

  insert into public.workout_sessions (
    session_id, user_id, routine_title, started_at, ended_at, total_sets, total_reps, volume_kg, updated_at
  ) values (
    session_id, uid, coalesce(routine_title, ''), started_at, ended_at,
    coalesce(total_sets, 0), coalesce(total_reps, 0), coalesce(volume_kg, 0), now()
  )
  on conflict (session_id) do update set
    user_id = uid,
    routine_title = excluded.routine_title,
    started_at = excluded.started_at,
    ended_at = excluded.ended_at,
    total_sets = excluded.total_sets,
    total_reps = excluded.total_reps,
    volume_kg = excluded.volume_kg,
    updated_at = now();
end;
$$;

revoke all on function public.upsert_workout_session(uuid,text,timestamptz,timestamptz,int,int,numeric) from public;
grant execute on function public.upsert_workout_session(uuid,text,timestamptz,timestamptz,int,int,numeric) to authenticated;

create or replace function public.list_workout_sessions_for_user(
  target_user_id uuid,
  from_ts timestamptz default null,
  to_ts timestamptz default null,
  limit_count int default 200
)
returns table (
  session_id uuid,
  routine_title text,
  started_at timestamptz,
  ended_at timestamptz,
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
  if uid <> target_user_id and public.are_friends(uid, target_user_id) = false then
    raise exception 'Not friends';
  end if;

  return query
  select w.session_id, w.routine_title, w.started_at, w.ended_at, w.total_sets, w.total_reps, w.volume_kg::double precision
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
  latest_ended_at timestamptz,
  longest_duration_seconds int
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
  if uid <> target_user_id and public.are_friends(uid, target_user_id) = false then
    raise exception 'Not friends';
  end if;

  return query
  select
    count(*)::int,
    coalesce(max(volume_kg::double precision), 0),
    coalesce(max(total_reps), 0),
    coalesce(max(total_sets), 0),
    max(ended_at),
    coalesce(max(extract(epoch from (ended_at - started_at))), 0)::int
  from public.workout_sessions
  where user_id = target_user_id;
end;
$$;

revoke all on function public.workout_stats_for_user_row(uuid) from public;
grant execute on function public.workout_stats_for_user_row(uuid) to authenticated;

-- Permissions (RLS still enforced)
revoke all on public.workout_sessions from anon, public;
grant select, insert, update, delete on public.workout_sessions to authenticated;

-- Reload schema if needed:
-- notify pgrst, 'reload schema';
