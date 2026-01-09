-- Detail tables + bundle RPC for workout sessions (owner write, friends read via RPC)

create table if not exists public.workout_exercises_cloud (
  user_id uuid not null,
  session_id uuid not null,
  exercise_id uuid not null,
  name text not null,
  order_index int not null default 0,
  created_at timestamptz not null default now(),
  primary key (user_id, exercise_id)
);

create index if not exists workout_exercises_cloud_idx
  on public.workout_exercises_cloud (user_id, session_id, order_index);

create table if not exists public.workout_sets_cloud (
  user_id uuid not null,
  session_id uuid not null,
  set_id uuid not null,
  exercise_id uuid not null,
  order_index int not null default 0,
  reps int not null default 0,
  weight_kg double precision not null default 0,
  is_warmup boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (user_id, set_id)
);

create index if not exists workout_sets_cloud_idx
  on public.workout_sets_cloud (user_id, session_id, exercise_id, order_index);

alter table public.workout_exercises_cloud enable row level security;
alter table public.workout_exercises_cloud force row level security;
alter table public.workout_sets_cloud enable row level security;
alter table public.workout_sets_cloud force row level security;

drop policy if exists wex_select_self on public.workout_exercises_cloud;
create policy wex_select_self
  on public.workout_exercises_cloud
  for select
  using (user_id = auth.uid());

drop policy if exists wex_insert_self on public.workout_exercises_cloud;
create policy wex_insert_self
  on public.workout_exercises_cloud
  for insert
  with check (user_id = auth.uid());

drop policy if exists wex_update_self on public.workout_exercises_cloud;
create policy wex_update_self
  on public.workout_exercises_cloud
  for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists wex_delete_self on public.workout_exercises_cloud;
create policy wex_delete_self
  on public.workout_exercises_cloud
  for delete
  using (user_id = auth.uid());

drop policy if exists wset_select_self on public.workout_sets_cloud;
create policy wset_select_self
  on public.workout_sets_cloud
  for select
  using (user_id = auth.uid());

drop policy if exists wset_insert_self on public.workout_sets_cloud;
create policy wset_insert_self
  on public.workout_sets_cloud
  for insert
  with check (user_id = auth.uid());

drop policy if exists wset_update_self on public.workout_sets_cloud;
create policy wset_update_self
  on public.workout_sets_cloud
  for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists wset_delete_self on public.workout_sets_cloud;
create policy wset_delete_self
  on public.workout_sets_cloud
  for delete
  using (user_id = auth.uid());

-- Bundle upsert (owner only)
create or replace function public.upsert_workout_session_bundle(bundle jsonb)
returns table (ok boolean)
language plpgsql
security definer
set search_path = public
as $$
declare
  target_user uuid;
  sid uuid;
begin
  if auth.uid() is null then
    raise exception 'unauthorized';
  end if;
  target_user := (bundle->>'user_id')::uuid;
  sid := (bundle->>'session_id')::uuid;
  if target_user is null or target_user <> auth.uid() then
    raise exception 'forbidden';
  end if;

  -- upsert summary
  perform public.upsert_workout_session(
    sid,
    coalesce(bundle->>'routine_title',''),
    (bundle->>'started_at')::timestamptz,
    (bundle->>'ended_at')::timestamptz,
    coalesce((bundle->>'total_sets')::int,0),
    coalesce((bundle->>'total_reps')::int,0),
    coalesce((bundle->>'volume_kg')::double precision,0)
  );

  -- replace exercises/sets
  delete from public.workout_sets_cloud where user_id = target_user and session_id = sid;
  delete from public.workout_exercises_cloud where user_id = target_user and session_id = sid;

  insert into public.workout_exercises_cloud (user_id, session_id, exercise_id, name, order_index)
  select target_user, sid,
         (e->>'exercise_id')::uuid,
         coalesce(e->>'name',''),
         coalesce((e->>'order_index')::int, 0)
  from jsonb_array_elements(bundle->'exercises') as e;

  insert into public.workout_sets_cloud (user_id, session_id, set_id, exercise_id, order_index, reps, weight_kg, is_warmup)
  select target_user, sid,
         (s->>'set_id')::uuid,
         (s->>'exercise_id')::uuid,
         coalesce((s->>'order_index')::int, 0),
         coalesce((s->>'reps')::int, 0),
         coalesce((s->>'weight_kg')::double precision, 0),
         coalesce((s->>'is_warmup')::boolean, false)
  from jsonb_array_elements(bundle->'sets') as s;

  return query select true as ok;
end;
$$;

revoke all on function public.upsert_workout_session_bundle(jsonb) from public;
grant execute on function public.upsert_workout_session_bundle(jsonb) to authenticated;

-- Bundle fetch (friend/self)
create or replace function public.get_workout_session_bundle(session_id text)
returns table (bundle jsonb)
language plpgsql
security definer
set search_path = public
as $$
declare
  sid uuid := session_id::uuid;
  owner uuid;
begin
  if auth.uid() is null then
    raise exception 'unauthorized';
  end if;

  select user_id into owner from public.workout_sessions_cloud where session_id = sid limit 1;
  if owner is null then
    return;
  end if;

  if owner <> auth.uid() and not public.are_friends(auth.uid(), owner) then
    raise exception 'forbidden';
  end if;

  return query
  select jsonb_build_object(
    'session', jsonb_build_object(
      'session_id', w.session_id,
      'user_id', w.user_id,
      'routine_title', w.routine_title,
      'started_at', w.started_at,
      'ended_at', w.ended_at,
      'total_sets', w.total_sets,
      'total_reps', w.total_reps,
      'volume_kg', w.volume_kg
    ),
    'exercises', coalesce((
      select jsonb_agg(jsonb_build_object(
        'exercise_id', e.exercise_id,
        'name', e.name,
        'order_index', e.order_index
      ) order by e.order_index)
      from public.workout_exercises_cloud e
      where e.user_id = owner and e.session_id = sid
    ), '[]'::jsonb),
    'sets', coalesce((
      select jsonb_agg(jsonb_build_object(
        'set_id', s.set_id,
        'exercise_id', s.exercise_id,
        'order_index', s.order_index,
        'reps', s.reps,
        'weight_kg', s.weight_kg,
        'is_warmup', s.is_warmup
      ) order by s.order_index)
      from public.workout_sets_cloud s
      where s.user_id = owner and s.session_id = sid
    ), '[]'::jsonb)
  ) as bundle
  from public.workout_sessions_cloud w
  where w.user_id = owner and w.session_id = sid
  limit 1;
end;
$$;

revoke all on function public.get_workout_session_bundle(text) from public;
grant execute on function public.get_workout_session_bundle(text) to authenticated;

-- Permissions
revoke all on public.workout_exercises_cloud from anon, public;
grant select, insert, update, delete on public.workout_exercises_cloud to authenticated;
revoke all on public.workout_sets_cloud from anon, public;
grant select, insert, update, delete on public.workout_sets_cloud to authenticated;
