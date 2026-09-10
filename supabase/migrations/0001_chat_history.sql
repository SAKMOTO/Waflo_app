-- ============================================================
-- WAFLO CHAT HISTORY
-- Run this ENTIRE file in the Supabase SQL editor for project
-- xzjpevmvereokrhalsmy:
--   https://supabase.com/dashboard/project/xzjpevmvereokrhalsmy/sql/new
-- It is idempotent (safe to re-run).
-- ============================================================

create extension if not exists pgcrypto;

-- ============================================================
-- CONVERSATIONS (one row per chat thread, owned by the user)
-- ============================================================
create table if not exists public.conversations (
  id         uuid        primary key default gen_random_uuid(),
  user_id    uuid        not null references auth.users (id) on delete cascade,
  title      text        not null default 'New chat',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ============================================================
-- MESSAGES (each turn inside a conversation)
-- ============================================================
create table if not exists public.messages (
  id              uuid        primary key default gen_random_uuid(),
  conversation_id uuid        not null references public.conversations (id) on delete cascade,
  user_id         uuid        not null references auth.users (id) on delete cascade,
  role            text        not null check (role in ('user', 'assistant', 'system')),
  content         text        not null,
  metadata        jsonb       not null default '{}'::jsonb,
  created_at      timestamptz not null default now()
);

-- ============================================================
-- INDEXES (note: both are on the CORRECT tables)
-- ============================================================
create index if not exists idx_conversations_user_updated
  on public.conversations (user_id, updated_at desc);

create index if not exists idx_messages_conversation_created
  on public.messages (conversation_id, created_at asc);

create index if not exists idx_messages_user_created
  on public.messages (user_id, created_at desc);

-- ============================================================
-- UPDATED_AT FUNCTION
-- ============================================================
create or replace function public.handle_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ============================================================
-- CONVERSATION UPDATE TRIGGER (title rename etc. bumps updated_at)
-- ============================================================
drop trigger if exists trg_conversations_updated_at on public.conversations;
create trigger trg_conversations_updated_at
  before update on public.conversations
  for each row execute function public.handle_updated_at();

-- ============================================================
-- NEW MESSAGE -> CONVERSATION MOVES TO TOP
-- Whenever a message is inserted, bump that conversation's updated_at so
-- the sidebar reorders (most recent first).
-- ============================================================
create or replace function public.handle_new_message()
returns trigger language plpgsql as $$
begin
  update public.conversations
  set updated_at = now()
  where id = new.conversation_id
    and user_id = new.user_id;
  return new;
end;
$$;

drop trigger if exists trg_message_updates_conversation on public.messages;
create trigger trg_message_updates_conversation
  after insert on public.messages
  for each row execute function public.handle_new_message();

-- ============================================================
-- ROW LEVEL SECURITY: users only see/change their own rows
-- ============================================================
alter table public.conversations enable row level security;
alter table public.messages      enable row level security;

-- ---------- conversations ----------
drop policy if exists "conversations_select_own" on public.conversations;
create policy "conversations_select_own" on public.conversations
  for select using (auth.uid() = user_id);

drop policy if exists "conversations_insert_own" on public.conversations;
create policy "conversations_insert_own" on public.conversations
  for insert with check (auth.uid() = user_id);

drop policy if exists "conversations_update_own" on public.conversations;
create policy "conversations_update_own" on public.conversations
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "conversations_delete_own" on public.conversations;
create policy "conversations_delete_own" on public.conversations
  for delete using (auth.uid() = user_id);

-- ---------- messages ----------
drop policy if exists "messages_select_own" on public.messages;
create policy "messages_select_own" on public.messages
  for select using (auth.uid() = user_id);

drop policy if exists "messages_insert_own" on public.messages;
create policy "messages_insert_own" on public.messages
  for insert with check (auth.uid() = user_id);

drop policy if exists "messages_update_own" on public.messages;
create policy "messages_update_own" on public.messages
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "messages_delete_own" on public.messages;
create policy "messages_delete_own" on public.messages
  for delete using (auth.uid() = user_id);