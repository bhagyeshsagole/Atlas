-- Phase B Prompt 4: Friend-safe workout session summaries + stats

-- A) Table
create table if not exists public.workout_session_summaries (
  session_id uuid primary key,
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

create index if not exists workout_session_summaries_user_id_idx
  on public.workout_session_summaries(user_id);
create index if not exists workout_session_summaries_ended_at_idx
  on public.workout_session_summaries(ended_at);

-- Updated_at trigger
create or replace function public._wss_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists wss_updated_at_trg on public.workout_session_summaries;
create trigger wss_updated_at_trg
before update on public.workout_session_summaries
for each row execute function public._wss_set_updated_at();

-- RLS
alter table public.workout_session_summaries enable row level security;
alter table public.workout_session_summaries force row level security;

drop policy if exists wss_select_self on public.workout_session_summaries;
create policy wss_select_self
  on public.workout_session_summaries
  for select
  using (user_id = auth.uid());

-- Recommend writes via RPC only
revoke insert, update, delete on public.workout_session_summaries from authenticated;

-- B) RPC upsert (uses auth.uid())
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

  insert into public.workout_session_summaries (
    session_id, user_id, routine_title, started_at, ended_at,
    total_sets, total_reps, volume_kg, updated_at
  ) values (
    session_id, uid, routine_title, started_at, ended_at,
    coalesce(total_sets, 0), coalesce(total_reps, 0), coalesce(volume_kg, 0), now()
  )
  on conflict (session_id) do update set
    user_id     = excluded.user_id,
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

-- C) Helper: are friends
create or replace function public.are_friends(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.friends f
    where f.user_a = least(a,b)
      and f.user_b = greatest(a,b)
  );
$$;

revoke all on function public.are_friends(uuid,uuid) from public;
grant execute on function public.are_friends(uuid,uuid) to authenticated;

-- D) RPC: list sessions (self or friend)
create or replace function public.list_workout_sessions_for_user(
  target_user_id uuid,
  from_ts timestamptz default null,
  to_ts timestamptz default null,
  limit_count int default 60
)
returns table (
  session_id uuid,
  user_id uuid,
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

  if target_user_id <> uid and public.are_friends(uid, target_user_id) = false then
    raise exception 'Not friends';
  end if;

  return query
  select w.session_id, w.user_id, w.routine_title, w.started_at, w.ended_at,
         w.total_sets, w.total_reps, w.volume_kg
  from public.workout_session_summaries w
  where w.user_id = target_user_id
    and (from_ts is null or w.ended_at >= from_ts)
    and (to_ts is null or w.ended_at <= to_ts)
  order by w.ended_at desc
  limit greatest(1, least(limit_count, 200));
end;
$$;

revoke all on function public.list_workout_sessions_for_user(uuid,timestamptz,timestamptz,int) from public;
grant execute on function public.list_workout_sessions_for_user(uuid,timestamptz,timestamptz,int) to authenticated;

-- E) RPC: friend/self stats
create or replace function public.workout_stats_for_user(target_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  result jsonb;
begin
  if uid is null then
    raise exception 'auth.uid() is required';
  end if;

  if target_user_id <> uid and public.are_friends(uid, target_user_id) = false then
    raise exception 'Not friends';
  end if;

  select jsonb_build_object(
    'sessions_total', count(*),
    'best_volume_kg', coalesce(max(volume_kg), 0),
    'best_total_reps', coalesce(max(total_reps), 0),
    'best_total_sets', coalesce(max(total_sets), 0),
    'latest_ended_at', max(ended_at),
    'longest_duration_seconds',
      coalesce(max(extract(epoch from (ended_at - started_at))), 0)
  )
  into result
  from public.workout_session_summaries
  where user_id = target_user_id;

  return result;
end;
$$;

revoke all on function public.workout_stats_for_user(uuid) from public;
grant execute on function public.workout_stats_for_user(uuid) to authenticated;

-- E2) RPC: friend/self stats (row result for easy decoding)
create or replace function public.workout_stats_for_user_row(target_user_id uuid)
returns table (
  sessions_total bigint,
  best_volume_kg double precision,
  best_total_reps int,
  best_total_sets int,
  latest_ended_at timestamptz,
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

  if target_user_id <> uid and public.are_friends(uid, target_user_id) = false then
    raise exception 'Not friends';
  end if;

  return query
  select
    count(*) as sessions_total,
    coalesce(max(volume_kg), 0) as best_volume_kg,
    coalesce(max(total_reps), 0) as best_total_reps,
    coalesce(max(total_sets), 0) as best_total_sets,
    max(ended_at) as latest_ended_at,
    coalesce(max(extract(epoch from (ended_at - started_at))), 0) as longest_duration_seconds
  from public.workout_session_summaries
  where user_id = target_user_id;
end;
$$;

revoke all on function public.workout_stats_for_user_row(uuid) from public;
grant execute on function public.workout_stats_for_user_row(uuid) to authenticated;

-- F) Permissions for table
revoke all on public.workout_session_summaries from anon, authenticated, public;
grant select on public.workout_session_summaries to authenticated;

-- G) Schema cache reload (run if needed)
-- notify pgrst, 'reload schema';

-- H) Sanity checks (replace <USER_A>, <USER_B>, <SESSION_ID>)
-- set local role authenticated;
-- select set_config('request.jwt.claim.role', 'authenticated', true);
-- select set_config('request.jwt.claim.sub', '<USER_A>', true);
-- select public.upsert_workout_session('<SESSION_ID>'::uuid, 'Push Day', now()-interval '50 minutes', now(), 12, 120, 8400.0);
-- select * from public.list_workout_sessions_for_user('<USER_A>'::uuid, null, null, 10);
-- select public.workout_stats_for_user('<USER_A>'::uuid);
