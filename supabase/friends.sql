-- Friends + profiles + RLS + RPCs for Atlas
-- Run in Supabase SQL Editor to provision tables, policies, and functions.

-- 0) Extensions (uuid generation)
create extension if not exists "pgcrypto";

-- 1) PROFILES (reuse app schema; ensures lowercase emails and self-scoped RLS)
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text,
  display_name text,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_email_lowercase check (email is null or email = lower(email))
);

create unique index if not exists profiles_email_unique on public.profiles (lower(email));

-- Normalize any existing mixed-case emails so the constraint stays valid.
update public.profiles
set email = lower(trim(email))
where email is not null and email <> lower(trim(email));

-- Keep updated_at in sync on updates.
create or replace function public.set_profile_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_profile_updated_at();

-- Normalize email to lowercase on insert/update to avoid constraint failures.
create or replace function public._profiles_email_lowercase()
returns trigger
language plpgsql
as $$
begin
  if new.email is not null then
    new.email := lower(trim(new.email));
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_email_lowercase_trg on public.profiles;
create trigger profiles_email_lowercase_trg
before insert or update on public.profiles
for each row
execute function public._profiles_email_lowercase();

-- RLS for profiles
alter table public.profiles enable row level security;
alter table public.profiles force row level security;

drop policy if exists profiles_select_self on public.profiles;
create policy profiles_select_self on public.profiles
for select using (id = auth.uid());

drop policy if exists profiles_insert_self on public.profiles;
create policy profiles_insert_self on public.profiles
for insert with check (id = auth.uid());

drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles
for update using (id = auth.uid()) with check (id = auth.uid());

-- 2) FRIEND REQUESTS
create table if not exists public.friend_requests (
  id uuid primary key default gen_random_uuid(),
  from_user uuid not null references public.profiles(id) on delete cascade,
  to_user uuid not null references public.profiles(id) on delete cascade,
  status text not null check (status in ('pending','accepted','declined')),
  created_at timestamptz not null default now(),
  constraint friend_requests_no_self check (from_user <> to_user)
);

-- Prevent duplicate pending requests regardless of direction.
create unique index if not exists friend_requests_pending_unique
on public.friend_requests (
  least(from_user, to_user),
  greatest(from_user, to_user)
)
where status = 'pending';

create index if not exists friend_requests_from_user_idx on public.friend_requests(from_user);
create index if not exists friend_requests_to_user_idx on public.friend_requests(to_user);

-- RLS for friend_requests
alter table public.friend_requests enable row level security;
alter table public.friend_requests force row level security;

drop policy if exists friend_requests_select_own on public.friend_requests;
create policy friend_requests_select_own
on public.friend_requests
for select
using (auth.uid() in (from_user, to_user));

drop policy if exists friend_requests_insert_sender_pending on public.friend_requests;
create policy friend_requests_insert_sender_pending
on public.friend_requests
for insert
with check (from_user = auth.uid() and status = 'pending');

drop policy if exists friend_requests_update_receiver_response on public.friend_requests;
create policy friend_requests_update_receiver_response
on public.friend_requests
for update
using (to_user = auth.uid() and status = 'pending')
with check (to_user = auth.uid() and status in ('accepted','declined'));

drop policy if exists friend_requests_delete_own on public.friend_requests;
create policy friend_requests_delete_own
on public.friend_requests
for delete
using (auth.uid() in (from_user, to_user));

-- 3) FRIEND EDGES (canonical ordering)
create table if not exists public.friends (
  user_a uuid not null references public.profiles(id) on delete cascade,
  user_b uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint friends_no_self check (user_a <> user_b),
  constraint friends_canonical_order check (user_a < user_b),
  constraint friends_unique_pair primary key (user_a, user_b)
);

-- RLS for friends
alter table public.friends enable row level security;
alter table public.friends force row level security;

drop policy if exists friends_select_own on public.friends;
create policy friends_select_own
on public.friends
for select
using (auth.uid() in (user_a, user_b));

-- 4) RPCs
-- Lookup by normalized email (returns id + email only)
create or replace function public.lookup_profile_by_email(search_email text)
returns table (id uuid, email text)
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_email text;
begin
  normalized_email := lower(trim(search_email));
  if normalized_email is null or normalized_email = '' then
    return;
  end if;

  return query
  select p.id, p.email
  from public.profiles p
  where p.email = normalized_email
  limit 1;
end;
$$;

-- Send a friend request to an email (caller is from_user)
create or replace function public.send_friend_request(to_email text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_email text;
  recipient_id uuid;
  requester_id uuid := auth.uid();
  existing_pending boolean;
  already_friends boolean;
  new_request_id uuid;
begin
  if requester_id is null then
    raise exception 'auth.uid() is required';
  end if;

  normalized_email := lower(trim(to_email));
  if normalized_email is null or normalized_email = '' then
    raise exception 'Email is required';
  end if;

  select p.id into recipient_id
  from public.profiles p
  where p.email = normalized_email
  limit 1;

  if recipient_id is null then
    raise exception 'No profile found for that email';
  end if;

  if recipient_id = requester_id then
    raise exception 'Cannot send a request to yourself';
  end if;

  select exists (
    select 1
    from public.friend_requests fr
    where least(fr.from_user, fr.to_user) = least(requester_id, recipient_id)
      and greatest(fr.from_user, fr.to_user) = greatest(requester_id, recipient_id)
      and fr.status = 'pending'
  ) into existing_pending;

  if existing_pending then
    raise exception 'A pending request already exists for this pair';
  end if;

  select exists (
    select 1
    from public.friends f
    where f.user_a = least(requester_id, recipient_id)
      and f.user_b = greatest(requester_id, recipient_id)
  ) into already_friends;

  if already_friends then
    raise exception 'Users are already friends';
  end if;

  insert into public.friend_requests (from_user, to_user, status)
  values (requester_id, recipient_id, 'pending')
  returning id into new_request_id;

  return new_request_id;
end;
$$;

-- Respond to a friend request (accept/decline). Caller must be to_user.
create or replace function public.respond_friend_request(request_id uuid, decision text)
returns public.friend_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  responder_id uuid := auth.uid();
  normalized_decision text;
  req public.friend_requests%rowtype;
begin
  if responder_id is null then
    raise exception 'auth.uid() is required';
  end if;

  normalized_decision := lower(trim(decision));
  if normalized_decision not in ('accepted','declined') then
    raise exception 'Decision must be accepted or declined';
  end if;

  select * into req
  from public.friend_requests fr
  where fr.id = request_id
  for update;

  if not found then
    raise exception 'Friend request not found';
  end if;

  if req.to_user <> responder_id then
    raise exception 'Only the recipient may respond to this request';
  end if;

  if req.status <> 'pending' then
    raise exception 'This request has already been handled';
  end if;

  update public.friend_requests fr
  set status = normalized_decision
  where fr.id = request_id;

  if normalized_decision = 'accepted' then
    insert into public.friends (user_a, user_b)
    values (least(req.from_user, req.to_user), greatest(req.from_user, req.to_user))
    on conflict do nothing;
  end if;

  return query
  select fr.*
  from public.friend_requests fr
  where fr.id = request_id;
end;
$$;

-- RPC privileges
revoke all on function public.lookup_profile_by_email(text) from public;
revoke all on function public.send_friend_request(text) from public;
revoke all on function public.respond_friend_request(uuid, text) from public;

grant execute on function public.lookup_profile_by_email(text) to authenticated;
grant execute on function public.send_friend_request(text) to authenticated;
grant execute on function public.respond_friend_request(uuid, text) to authenticated;

-- RPC: safe email hydration for related users
create or replace function public.profiles_public_lookup(user_ids uuid[])
returns table (id uuid, email text)
language plpgsql
security definer
set search_path = public
as $$
declare
  requester uuid := auth.uid();
  id_count int;
begin
  if requester is null then
    return;
  end if;

  id_count := coalesce(array_length(user_ids, 1), 0);
  if id_count = 0 then
    return;
  end if;
  if id_count > 50 then
    raise exception 'Too many ids (max 50)';
  end if;

  return query
  with targets as (
    select unnest(user_ids) as id
  ),
  allowed as (
    select t.id
    from targets t
    where t.id is not null
      and (
        exists (
          select 1 from public.friends f
          where (f.user_a = requester and f.user_b = t.id)
             or (f.user_b = requester and f.user_a = t.id)
        )
        or exists (
          select 1 from public.friend_requests fr
          where (fr.from_user = requester and fr.to_user = t.id)
             or (fr.to_user = requester and fr.from_user = t.id)
        )
      )
  )
  select p.id, p.email
  from public.profiles p
  join allowed a on a.id = p.id;
end;
$$;

revoke all on function public.profiles_public_lookup(uuid[]) from public;
grant execute on function public.profiles_public_lookup(uuid[]) to authenticated;
