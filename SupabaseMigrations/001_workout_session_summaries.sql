-- Workout session summaries (owner-only for now)

-- Table
create table if not exists public.workout_session_summaries (
  session_id uuid primary key,
  owner_id uuid not null default auth.uid(),
  routine_title text not null,
  started_at timestamptz null,
  ended_at timestamptz not null,
  total_sets int not null,
  total_reps int not null,
  volume_kg double precision not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists workout_session_summaries_owner_ended_idx
  on public.workout_session_summaries (owner_id, ended_at desc);

-- updated_at trigger
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

drop policy if exists wss_owner_select on public.workout_session_summaries;
create policy wss_owner_select
  on public.workout_session_summaries
  for select
  using (owner_id = auth.uid());

drop policy if exists wss_owner_insert on public.workout_session_summaries;
create policy wss_owner_insert
  on public.workout_session_summaries
  for insert
  with check (owner_id = auth.uid());

drop policy if exists wss_owner_update on public.workout_session_summaries;
create policy wss_owner_update
  on public.workout_session_summaries
  for update
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

drop policy if exists wss_owner_delete on public.workout_session_summaries;
create policy wss_owner_delete
  on public.workout_session_summaries
  for delete
  using (owner_id = auth.uid());

-- RPC: upsert_workout_session
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
  existing_owner uuid;
begin
  if uid is null then
    raise exception 'auth.uid() is required';
  end if;

  select owner_id into existing_owner from public.workout_session_summaries where session_id = session_id;
  if existing_owner is not null and existing_owner <> uid then
    raise exception 'unauthorized to update this session';
  end if;

  insert into public.workout_session_summaries (
    session_id, owner_id, routine_title, started_at, ended_at, total_sets, total_reps, volume_kg, updated_at
  ) values (
    session_id, uid, coalesce(routine_title, ''), started_at, ended_at,
    coalesce(total_sets, 0), coalesce(total_reps, 0), coalesce(volume_kg, 0), now()
  )
  on conflict (session_id) do update set
    owner_id     = uid,
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

-- Permissions
revoke all on public.workout_session_summaries from anon, public;
grant select, insert, update, delete on public.workout_session_summaries to authenticated;

-- Debug sanity (run manually if needed):
-- set local role authenticated;
-- select set_config('request.jwt.claim.role', 'authenticated', true);
-- select set_config('request.jwt.claim.sub', '<YOUR_AUTH_USER_ID>', true);
-- select public.upsert_workout_session(
--   '<SESSION_UUID>'::uuid, 'Test', now()-interval '30 minutes', now(), 10, 100, 5000.0
-- );
-- select * from public.workout_session_summaries where owner_id = auth.uid();

-- If PostgREST schema cache complains (PGRST205), run:
-- notify pgrst, 'reload schema';
