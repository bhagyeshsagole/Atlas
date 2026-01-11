-- Workout history (append-only)
create table if not exists public.workout_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  local_id text not null,
  routine_id uuid null,
  routine_title text null,
  started_at timestamptz not null,
  ended_at timestamptz not null,
  total_sets int not null,
  total_reps int not null,
  total_volume_kg double precision not null,
  created_at timestamptz not null default now(),
  unique (user_id, local_id)
);

create table if not exists public.session_exercises (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.workout_sessions(id) on delete cascade,
  user_id uuid not null references auth.users(id),
  local_id text not null,
  name text not null,
  sort_index int not null,
  created_at timestamptz default now(),
  unique (user_id, local_id)
);

create table if not exists public.session_sets (
  id uuid primary key default gen_random_uuid(),
  exercise_id uuid not null references public.session_exercises(id) on delete cascade,
  session_id uuid not null references public.workout_sessions(id) on delete cascade,
  user_id uuid not null references auth.users(id),
  local_id text not null,
  weight_kg double precision not null,
  reps int not null,
  is_bodyweight boolean not null default false,
  is_warmup boolean not null default false,
  created_at timestamptz default now(),
  unique (user_id, local_id)
);

create table if not exists public.session_set_tags (
  id uuid primary key default gen_random_uuid(),
  set_id uuid not null references public.session_sets(id) on delete cascade,
  user_id uuid not null references auth.users(id),
  tag text not null,
  created_at timestamptz default now(),
  unique (set_id, tag)
);

-- Routines (deletable)
create table if not exists public.routines (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  local_id text not null,
  title text not null,
  tags text[] not null default '{}'::text[],
  source text not null default 'user',
  coach_name text null,
  payload jsonb not null,
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (user_id, local_id)
);

-- Friendships (for future sharing)
create table if not exists public.friendships (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references auth.users(id),
  addressee_id uuid not null references auth.users(id),
  status text not null,
  created_at timestamptz default now(),
  unique (requester_id, addressee_id)
);

-- Helper: check accepted friendship (used for select policies)
create or replace function public.is_friend(viewer uuid, owner uuid)
returns boolean
language sql
security definer
stable
as $$
  select exists (
    select 1 from public.friendships f
    where (
      (f.requester_id = viewer and f.addressee_id = owner)
      or (f.requester_id = owner and f.addressee_id = viewer)
    )
    and f.status = 'accepted'
  );
$$;

-- RLS enable
alter table public.workout_sessions enable row level security;
alter table public.session_exercises enable row level security;
alter table public.session_sets enable row level security;
alter table public.session_set_tags enable row level security;
alter table public.routines enable row level security;
alter table public.friendships enable row level security;

-- History: owner insert/select only, no updates/deletes
create policy "sessions_insert_owner" on public.workout_sessions for insert with check (auth.uid() = user_id);
create policy "sessions_select_owner_or_friend" on public.workout_sessions for select using (auth.uid() = user_id or public.is_friend(auth.uid(), user_id));
create policy "sessions_update_block" on public.workout_sessions for update using (false);
create policy "sessions_delete_block" on public.workout_sessions for delete using (false);

create policy "exercises_insert_owner" on public.session_exercises for insert with check (auth.uid() = user_id);
create policy "exercises_select_owner_or_friend" on public.session_exercises for select using (auth.uid() = user_id or public.is_friend(auth.uid(), user_id));
create policy "exercises_update_block" on public.session_exercises for update using (false);
create policy "exercises_delete_block" on public.session_exercises for delete using (false);

create policy "sets_insert_owner" on public.session_sets for insert with check (auth.uid() = user_id);
create policy "sets_select_owner_or_friend" on public.session_sets for select using (auth.uid() = user_id or public.is_friend(auth.uid(), user_id));
create policy "sets_update_block" on public.session_sets for update using (false);
create policy "sets_delete_block" on public.session_sets for delete using (false);

create policy "set_tags_insert_owner" on public.session_set_tags for insert with check (auth.uid() = user_id);
create policy "set_tags_select_owner_or_friend" on public.session_set_tags for select using (auth.uid() = user_id or public.is_friend(auth.uid(), user_id));
create policy "set_tags_update_block" on public.session_set_tags for update using (false);
create policy "set_tags_delete_block" on public.session_set_tags for delete using (false);

-- Routines: owner CRUD
create policy "routines_select_owner" on public.routines for select using (auth.uid() = user_id);
create policy "routines_insert_owner" on public.routines for insert with check (auth.uid() = user_id);
create policy "routines_update_owner" on public.routines for update using (auth.uid() = user_id);
create policy "routines_delete_owner" on public.routines for delete using (auth.uid() = user_id);

-- Friendships: owner CRUD
create policy "friendships_select_self" on public.friendships for select using (auth.uid() = requester_id or auth.uid() = addressee_id);
create policy "friendships_insert_self" on public.friendships for insert with check (auth.uid() = requester_id);
create policy "friendships_update_self" on public.friendships for update using (auth.uid() = requester_id or auth.uid() = addressee_id);
create policy "friendships_delete_self" on public.friendships for delete using (false);
