-- Workout session cloud summaries (per-user)

create table if not exists public.workout_sessions_cloud (
  user_id uuid not null default auth.uid(),
  session_id uuid not null,
  routine_title text not null,
  started_at timestamptz null,
  ended_at timestamptz not null,
  total_sets int not null default 0,
  total_reps int not null default 0,
  volume_kg double precision not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, session_id)
);

create index if not exists workout_sessions_cloud_user_ended_idx
  on public.workout_sessions_cloud (user_id, ended_at desc);

create or replace function public._ws_cloud_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists ws_cloud_updated_at_trg on public.workout_sessions_cloud;
create trigger ws_cloud_updated_at_trg
before update on public.workout_sessions_cloud
for each row execute function public._ws_cloud_set_updated_at();

alter table public.workout_sessions_cloud enable row level security;
alter table public.workout_sessions_cloud force row level security;

drop policy if exists ws_cloud_select_self on public.workout_sessions_cloud;
create policy ws_cloud_select_self
  on public.workout_sessions_cloud
  for select
  using (user_id = auth.uid());

drop policy if exists ws_cloud_insert_self on public.workout_sessions_cloud;
create policy ws_cloud_insert_self
  on public.workout_sessions_cloud
  for insert
  with check (user_id = auth.uid());

drop policy if exists ws_cloud_update_self on public.workout_sessions_cloud;
create policy ws_cloud_update_self
  on public.workout_sessions_cloud
  for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists ws_cloud_delete_self on public.workout_sessions_cloud;
create policy ws_cloud_delete_self
  on public.workout_sessions_cloud
  for delete
  using (user_id = auth.uid());

create or replace function public.upsert_workout_session(
  session_id uuid,
  routine_title text,
  started_at timestamptz,
  ended_at timestamptz,
  total_sets int,
  total_reps int,
  volume_kg double precision
)
returns public.workout_sessions_cloud
language plpgsql
security definer
set search_path = public
as $$
declare
  out_row public.workout_sessions_cloud%rowtype;
begin
  if auth.uid() is null then
    raise exception 'unauthorized';
  end if;

  insert into public.workout_sessions_cloud(
    user_id, session_id, routine_title, started_at, ended_at, total_sets, total_reps, volume_kg, updated_at
  )
  values (
    auth.uid(), session_id, coalesce(routine_title, ''), started_at, ended_at,
    coalesce(total_sets, 0), coalesce(total_reps, 0), coalesce(volume_kg, 0), now()
  )
  on conflict (user_id, session_id)
  do update set
    routine_title = excluded.routine_title,
    started_at = excluded.started_at,
    ended_at = excluded.ended_at,
    total_sets = excluded.total_sets,
    total_reps = excluded.total_reps,
    volume_kg = excluded.volume_kg,
    updated_at = now()
  returning * into out_row;

  return out_row;
end;
$$;

revoke all on function public.upsert_workout_session(uuid,text,timestamptz,timestamptz,int,int,double precision) from public;
grant execute on function public.upsert_workout_session(uuid,text,timestamptz,timestamptz,int,int,double precision) to authenticated;

revoke all on public.workout_sessions_cloud from anon, public;
grant select, insert, update, delete on public.workout_sessions_cloud to authenticated;

-- Schema cache reload if needed:
-- notify pgrst, 'reload schema';

-- Sanity (run manually):
-- set local role authenticated;
-- select set_config('request.jwt.claim.role', 'authenticated', true);
-- select set_config('request.jwt.claim.sub', '<USER_ID>', true);
-- select public.upsert_workout_session(
--   '<SESSION_UUID>'::uuid, 'Test', now()-interval '30 minutes', now(), 10, 120, 5000.0
-- );
-- select * from public.workout_sessions_cloud where user_id = auth.uid();
