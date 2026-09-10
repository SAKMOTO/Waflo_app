-- ============================================================
-- WAFLO USER PROFILES, PREFERENCES & AVATAR STORAGE
-- Run this ENTIRE file in the Supabase SQL editor for project
-- xzjpevmvereokrhalsmy:
--   https://supabase.com/dashboard/project/xzjpevmvereokrhalsmy/sql/new
-- It is idempotent (safe to re-run). Requires 0001_chat_history.sql
-- to have been run first (it already is).
-- ============================================================
-- NOTE: the app ships with a local fallback (localStorage) so everything
-- works even before this file is applied. Once applied, profiles and
-- preferences are persisted in the database and synced automatically.
-- ============================================================

-- ============================================================
-- PROFILES (one row per signed-in Google account)
-- ============================================================
create table if not exists public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default '',
  username     text,
  bio          text not null default '',
  avatar_url   text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

-- Usernames are unique (case-insensitive) but profile rows are optional.
create unique index if not exists idx_profiles_username
  on public.profiles (lower(username))
  where username is not null and username <> '';

-- ============================================================
-- USER PREFERENCES (theme + app behaviour per account)
-- ============================================================
create table if not exists public.user_preferences (
  id               uuid primary key references auth.users (id) on delete cascade,
  theme            text not null default 'midnight',
  default_agent    text not null default 'strobi',
  animations_enabled boolean not null default true,
  sound_enabled    boolean not null default true,
  reduce_motion    boolean not null default false,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  check (theme in ('midnight', 'ocean', 'aurora', 'ember'))
);

create index if not exists idx_user_preferences_id
  on public.user_preferences (id);

-- ============================================================
-- UPDATED_AT TRIGGERS
-- ============================================================
drop trigger if exists trg_profiles_updated_at on public.profiles;
create trigger trg_profiles_updated_at
  before update on public.profiles
  for each row execute function public.handle_updated_at();

drop trigger if exists trg_user_preferences_updated_at on public.user_preferences;
create trigger trg_user_preferences_updated_at
  before update on public.user_preferences
  for each row execute function public.handle_updated_at();

-- ============================================================
-- ROW LEVEL SECURITY
-- Profiles are semi-public (id, username, display name, avatar are
-- readable so usernames can stay unique); writes are strictly own-row.
-- ============================================================
alter table public.profiles enable row level security;
alter table public.user_preferences enable row level security;

drop policy if exists "profiles_select_public_info" on public.profiles;
create policy "profiles_select_public_info" on public.profiles
  for select using (true);

drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own" on public.profiles
  for insert with check (auth.uid() = id);

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own" on public.profiles
  for update using (auth.uid() = id) with check (auth.uid() = id);

drop policy if exists "profiles_delete_own" on public.profiles;
create policy "profiles_delete_own" on public.profiles
  for delete using (auth.uid() = id);

drop policy if exists "prefs_select_own" on public.user_preferences;
create policy "prefs_select_own" on public.user_preferences
  for select using (auth.uid() = id);

drop policy if exists "prefs_insert_own" on public.user_preferences;
create policy "prefs_insert_own" on public.user_preferences
  for insert with check (auth.uid() = id);

drop policy if exists "prefs_update_own" on public.user_preferences;
create policy "prefs_update_own" on public.user_preferences
  for update using (auth.uid() = id) with check (auth.uid() = id);

drop policy if exists "prefs_delete_own" on public.user_preferences;
create policy "prefs_delete_own" on public.user_preferences
  for delete using (auth.uid() = id);

-- ============================================================
-- AUTO-CREATE A ROW ON FIRST SIGN-UP
-- Any new Google / email user immediately gets a profile + preferences row.
-- ============================================================
create or replace function public.handle_new_user()
returns trigger language plpgsql as $$
begin
  insert into public.profiles (id)
    values (new.id)
    on conflict (id) do nothing;
  insert into public.user_preferences (id)
    values (new.id)
    on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists trg_handle_new_user on auth.users;
create trigger trg_handle_new_user
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Bootstrap the current authenticated users (in case the trigger landed
-- after their accounts already existed).
insert into public.profiles (id)
  select id from auth.users on conflict (id) do nothing;
insert into public.user_preferences (id)
  select id from auth.users on conflict (id) do nothing;

-- ============================================================
-- AVATAR STORAGE
-- Public bucket "avatars", files stored at {user_id}/profile.*
-- ============================================================
insert into storage.buckets (id, name, public)
  values ('avatars', 'avatars', true)
  on conflict (id) do nothing;

drop policy if exists "avatars_public_read" on storage.objects;
create policy "avatars_public_read" on storage.objects
  for select using (bucket_id = 'avatars');

drop policy if exists "avatars_owner_insert" on storage.objects;
create policy "avatars_owner_insert" on storage.objects
  for insert with check (
    bucket_id = 'avatars'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "avatars_owner_update" on storage.objects;
create policy "avatars_owner_update" on storage.objects
  for update using (
    bucket_id = 'avatars'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "avatars_owner_delete" on storage.objects;
create policy "avatars_owner_delete" on storage.objects
  for delete using (
    bucket_id = 'avatars'
    and auth.uid()::text = (storage.foldername(name))[1]
  );