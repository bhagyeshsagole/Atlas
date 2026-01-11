-- Adds training profile fields to profiles table
alter table public.profiles
    add column if not exists height_cm numeric,
    add column if not exists weight_kg numeric,
    add column if not exists workouts_per_week integer,
    add column if not exists training_goal text,
    add column if not exists experience_level text,
    add column if not exists limitations text,
    add column if not exists onboarding_completed boolean default false;

-- ensure onboarding_completed defaults to false for existing rows
update public.profiles set onboarding_completed = coalesce(onboarding_completed, false) where onboarding_completed is null;
