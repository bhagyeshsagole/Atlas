-- Align local_id expectations and ownership for Atlas sync

-- Ensure history tables have local_id and allow inserts with provided values
alter table public.workout_sessions
  add column if not exists local_id text;
update public.workout_sessions set local_id = coalesce(local_id, id::text);
alter table public.workout_sessions alter column local_id set not null;

alter table public.session_exercises
  add column if not exists local_id text;
update public.session_exercises set local_id = coalesce(local_id, id::text);
alter table public.session_exercises alter column local_id set not null;

alter table public.session_sets
  add column if not exists local_id text;
update public.session_sets set local_id = coalesce(local_id, id::text);
alter table public.session_sets alter column local_id set not null;

-- Routines: ensure local_id/user_id are present and non-null
alter table public.routines
  add column if not exists local_id text,
  add column if not exists is_coach_suggested boolean not null default false;
update public.routines set local_id = coalesce(local_id, id::text);

-- Keep user_id in sync with owner_user_id
alter table public.routines alter column user_id drop not null;
update public.routines set user_id = coalesce(user_id, owner_user_id);
alter table public.routines alter column user_id set not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'routines_owner_user_id_fkey'
  ) then
    alter table public.routines
      add constraint routines_owner_user_id_fkey
      foreign key (owner_user_id) references auth.users(id) on delete cascade;
  end if;
end$$;

create or replace function public.routines_set_user_id()
returns trigger language plpgsql as $$
begin
  if new.user_id is null then
    new.user_id = new.owner_user_id;
  end if;
  return new;
end;
$$;

drop trigger if exists routines_set_user_id on public.routines;
create trigger routines_set_user_id
before insert or update on public.routines
for each row execute function public.routines_set_user_id();

-- RLS for child tables via parent ownership (if policies are missing or too restrictive)
alter table public.session_exercises enable row level security;
alter table public.session_sets enable row level security;
alter table public.session_set_tags enable row level security;

drop policy if exists session_exercises_select_own on public.session_exercises;
create policy session_exercises_select_own on public.session_exercises
for select using (
  exists (
    select 1 from public.workout_sessions s
    where s.id = session_exercises.session_id
      and s.user_id = auth.uid()
  )
);

drop policy if exists session_exercises_insert_own on public.session_exercises;
create policy session_exercises_insert_own on public.session_exercises
for insert with check (
  exists (
    select 1 from public.workout_sessions s
    where s.id = session_exercises.session_id
      and s.user_id = auth.uid()
  )
);

drop policy if exists session_exercises_update_own on public.session_exercises;
create policy session_exercises_update_own on public.session_exercises
for update using (
  exists (
    select 1 from public.workout_sessions s
    where s.id = session_exercises.session_id
      and s.user_id = auth.uid()
  )
)
with check (
  exists (
    select 1 from public.workout_sessions s
    where s.id = session_exercises.session_id
      and s.user_id = auth.uid()
  )
);

drop policy if exists session_exercises_delete_own on public.session_exercises;
create policy session_exercises_delete_own on public.session_exercises
for delete using (
  exists (
    select 1 from public.workout_sessions s
    where s.id = session_exercises.session_id
      and s.user_id = auth.uid()
  )
);

drop policy if exists session_sets_select_own on public.session_sets;
create policy session_sets_select_own on public.session_sets
for select using (
  exists (
    select 1 from public.session_exercises e
    join public.workout_sessions s on s.id = e.session_id
    where e.id = session_sets.exercise_id
      and s.user_id = auth.uid()
  )
);

drop policy if exists session_sets_insert_own on public.session_sets;
create policy session_sets_insert_own on public.session_sets
for insert with check (
  exists (
    select 1 from public.session_exercises e
    join public.workout_sessions s on s.id = e.session_id
    where e.id = session_sets.exercise_id
      and s.user_id = auth.uid()
  )
);

drop policy if exists session_sets_update_own on public.session_sets;
create policy session_sets_update_own on public.session_sets
for update using (
  exists (
    select 1 from public.session_exercises e
    join public.workout_sessions s on s.id = e.session_id
    where e.id = session_sets.exercise_id
      and s.user_id = auth.uid()
  )
)
with check (
  exists (
    select 1 from public.session_exercises e
    join public.workout_sessions s on s.id = e.session_id
    where e.id = session_sets.exercise_id
      and s.user_id = auth.uid()
  )
);

drop policy if exists session_sets_delete_own on public.session_sets;
create policy session_sets_delete_own on public.session_sets
for delete using (
  exists (
    select 1 from public.session_exercises e
    join public.workout_sessions s on s.id = e.session_id
    where e.id = session_sets.exercise_id
      and s.user_id = auth.uid()
  )
);

drop policy if exists set_tags_select_own on public.session_set_tags;
create policy set_tags_select_own on public.session_set_tags
for select using (
  exists (
    select 1 from public.session_sets st
    join public.session_exercises e on e.id = st.exercise_id
    join public.workout_sessions s on s.id = e.session_id
    where st.id = session_set_tags.set_id
      and s.user_id = auth.uid()
  )
);

drop policy if exists set_tags_insert_own on public.session_set_tags;
create policy set_tags_insert_own on public.session_set_tags
for insert with check (
  exists (
    select 1 from public.session_sets st
    join public.session_exercises e on e.id = st.exercise_id
    join public.workout_sessions s on s.id = e.session_id
    where st.id = session_set_tags.set_id
      and s.user_id = auth.uid()
  )
);

drop policy if exists set_tags_update_own on public.session_set_tags;
create policy set_tags_update_own on public.session_set_tags
for update using (
  exists (
    select 1 from public.session_sets st
    join public.session_exercises e on e.id = st.exercise_id
    join public.workout_sessions s on s.id = e.session_id
    where st.id = session_set_tags.set_id
      and s.user_id = auth.uid()
  )
)
with check (
  exists (
    select 1 from public.session_sets st
    join public.session_exercises e on e.id = st.exercise_id
    join public.workout_sessions s on s.id = e.session_id
    where st.id = session_set_tags.set_id
      and s.user_id = auth.uid()
  )
);

drop policy if exists set_tags_delete_own on public.session_set_tags;
create policy set_tags_delete_own on public.session_set_tags
for delete using (
  exists (
    select 1 from public.session_sets st
    join public.session_exercises e on e.id = st.exercise_id
    join public.workout_sessions s on s.id = e.session_id
    where st.id = session_set_tags.set_id
      and s.user_id = auth.uid()
  )
);

-- Refresh schema cache
select pg_notify('pgrst', 'reload schema');
