-- Friend-accessible workout history via RPC (secure: requires friendship or self)

-- Helper: undirected friend check
create or replace function public.are_friends(a uuid, b uuid)
returns boolean
language sql
stable
as $$
  select exists(
    select 1 from public.friends
    where (user_a = a and user_b = b) or (user_a = b and user_b = a)
  );
$$;

revoke all on function public.are_friends(uuid,uuid) from public;
grant execute on function public.are_friends(uuid,uuid) to authenticated;

-- RPC: list friend/self workout sessions from workout_sessions_cloud
create or replace function public.list_workout_sessions_for_user(
  target_user_id text,
  from_ts timestamptz default null,
  to_ts timestamptz default null,
  limit_count int default 200
)
returns table(
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
  target uuid;
begin
  if auth.uid() is null then
    raise exception 'unauthorized';
  end if;
  target := target_user_id::uuid;
  if target <> auth.uid() and not public.are_friends(auth.uid(), target) then
    raise exception 'forbidden';
  end if;

  return query
  select
    w.session_id,
    w.routine_title,
    w.started_at,
    w.ended_at,
    w.total_sets,
    w.total_reps,
    w.volume_kg
  from public.workout_sessions_cloud w
  where w.user_id = target
    and (from_ts is null or w.ended_at >= from_ts)
    and (to_ts is null or w.ended_at <= to_ts)
  order by w.ended_at desc
  limit greatest(1, least(limit_count, 500));
end;
$$;

revoke all on function public.list_workout_sessions_for_user(text,timestamptz,timestamptz,int) from public;
grant execute on function public.list_workout_sessions_for_user(text,timestamptz,timestamptz,int) to authenticated;

-- RPC: stats for friend/self from workout_sessions_cloud
create or replace function public.workout_stats_for_user_row(target_user_id text)
returns table(
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
  target uuid;
begin
  if auth.uid() is null then
    raise exception 'unauthorized';
  end if;
  target := target_user_id::uuid;
  if target <> auth.uid() and not public.are_friends(auth.uid(), target) then
    raise exception 'forbidden';
  end if;

  return query
  select
    count(*)::int,
    coalesce(max(volume_kg), 0)::double precision,
    coalesce(max(total_reps), 0)::int,
    coalesce(max(total_sets), 0)::int,
    max(ended_at),
    0::int
  from public.workout_sessions_cloud
  where user_id = target;
end;
$$;

revoke all on function public.workout_stats_for_user_row(text) from public;
grant execute on function public.workout_stats_for_user_row(text) to authenticated;

-- Schema cache reload if needed:
-- notify pgrst, 'reload schema';
