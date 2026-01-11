-- Step 4: align columns + RLS for Atlas sync

-- Ensure required columns exist
alter table if exists public.workout_sessions
  add column if not exists user_id uuid,
  add column if not exists local_id uuid;
alter table if exists public.session_exercises
  add column if not exists user_id uuid,
  add column if not exists local_id uuid;
alter table if exists public.session_sets
  add column if not exists user_id uuid,
  add column if not exists local_id uuid;

alter table if exists public.routines
  add column if not exists user_id uuid,
  add column if not exists local_id uuid,
  add column if not exists is_deleted boolean not null default false;

-- Unique constraints for idempotent upserts
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'workout_sessions_user_local_id_key') then
    alter table public.workout_sessions add constraint workout_sessions_user_local_id_key unique (user_id, local_id);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'session_exercises_user_local_id_key') then
    alter table public.session_exercises add constraint session_exercises_user_local_id_key unique (user_id, local_id);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'session_sets_user_local_id_key') then
    alter table public.session_sets add constraint session_sets_user_local_id_key unique (user_id, local_id);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'routines_user_local_id_key') then
    alter table public.routines add constraint routines_user_local_id_key unique (user_id, local_id);
  end if;
end $$;

-- RLS with WITH CHECK for inserts/updates
alter table public.workout_sessions enable row level security;
alter table public.session_exercises enable row level security;
alter table public.session_sets enable row level security;
alter table public.session_set_tags enable row level security;
alter table public.routines enable row level security;

-- workout_sessions
drop policy if exists ws_select on public.workout_sessions;
drop policy if exists ws_insert on public.workout_sessions;
drop policy if exists ws_update on public.workout_sessions;
drop policy if exists ws_delete on public.workout_sessions;
create policy ws_select on public.workout_sessions for select using (user_id = auth.uid());
create policy ws_insert on public.workout_sessions for insert with check (user_id = auth.uid());
create policy ws_update on public.workout_sessions for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy ws_delete on public.workout_sessions for delete using (user_id = auth.uid());

-- session_exercises
drop policy if exists se_select on public.session_exercises;
drop policy if exists se_insert on public.session_exercises;
drop policy if exists se_update on public.session_exercises;
drop policy if exists se_delete on public.session_exercises;
create policy se_select on public.session_exercises for select using (user_id = auth.uid());
create policy se_insert on public.session_exercises for insert with check (user_id = auth.uid());
create policy se_update on public.session_exercises for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy se_delete on public.session_exercises for delete using (user_id = auth.uid());

-- session_sets
drop policy if exists ss_select on public.session_sets;
drop policy if exists ss_insert on public.session_sets;
drop policy if exists ss_update on public.session_sets;
drop policy if exists ss_delete on public.session_sets;
create policy ss_select on public.session_sets for select using (user_id = auth.uid());
create policy ss_insert on public.session_sets for insert with check (user_id = auth.uid());
create policy ss_update on public.session_sets for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy ss_delete on public.session_sets for delete using (user_id = auth.uid());

-- session_set_tags (ownership via parent set -> exercise -> session)
drop policy if exists st_select on public.session_set_tags;
drop policy if exists st_insert on public.session_set_tags;
drop policy if exists st_update on public.session_set_tags;
drop policy if exists st_delete on public.session_set_tags;
create policy st_select on public.session_set_tags for select using (
  exists (
    select 1 from public.session_sets s
    where s.id = session_set_tags.set_id and s.user_id = auth.uid()
  )
);
create policy st_insert on public.session_set_tags for insert with check (
  exists (
    select 1 from public.session_sets s
    where s.id = session_set_tags.set_id and s.user_id = auth.uid()
  )
);
create policy st_update on public.session_set_tags for update using (
  exists (
    select 1 from public.session_sets s
    where s.id = session_set_tags.set_id and s.user_id = auth.uid()
  )
) with check (
  exists (
    select 1 from public.session_sets s
    where s.id = session_set_tags.set_id and s.user_id = auth.uid()
  )
);
create policy st_delete on public.session_set_tags for delete using (
  exists (
    select 1 from public.session_sets s
    where s.id = session_set_tags.set_id and s.user_id = auth.uid()
  )
);

-- routines
drop policy if exists r_select on public.routines;
drop policy if exists r_insert on public.routines;
drop policy if exists r_update on public.routines;
drop policy if exists r_delete on public.routines;
create policy r_select on public.routines for select using (user_id = auth.uid());
create policy r_insert on public.routines for insert with check (user_id = auth.uid());
create policy r_update on public.routines for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy r_delete on public.routines for delete using (user_id = auth.uid());

-- Refresh schema cache
select pg_notify('pgrst', 'reload schema');
