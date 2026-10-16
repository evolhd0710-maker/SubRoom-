-- 가사방 공유 서버 스키마 (Supabase SQL Editor에 그대로 붙여넣고 Run)
-- 로그인 없이 누구나 읽고 올릴 수 있고, 수정/삭제는 곡을 올린 기기(소유 토큰)만 가능합니다.

create extension if not exists pgcrypto;

create table if not exists public.songs (
  id          uuid primary key default gen_random_uuid(),
  youtube_id  text not null check (youtube_id ~ '^[A-Za-z0-9_-]{11}$'),
  title       text not null check (char_length(title) between 1 and 120),
  artist      text not null default '' check (char_length(artist) <= 80),
  author      text not null default '익명' check (char_length(author) <= 40),
  lines       jsonb not null default '[]'::jsonb
              check (jsonb_typeof(lines) = 'array' and jsonb_array_length(lines) <= 600),
  plays       integer not null default 0,
  owner_token uuid not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index if not exists songs_created_idx on public.songs (created_at desc);
create index if not exists songs_plays_idx   on public.songs (plays desc);

alter table public.songs enable row level security;

drop policy if exists "songs readable by everyone" on public.songs;
create policy "songs readable by everyone" on public.songs for select using (true);

drop policy if exists "anyone can publish" on public.songs;
create policy "anyone can publish" on public.songs for insert with check (true);

-- owner_token은 외부에서 읽을 수 없도록 컬럼 단위로 권한을 줍니다.
revoke all on public.songs from anon, authenticated;
grant select (id, youtube_id, title, artist, author, lines, plays, created_at, updated_at)
  on public.songs to anon, authenticated;
grant insert (id, youtube_id, title, artist, author, lines, owner_token)
  on public.songs to anon, authenticated;

-- 수정: 소유 토큰이 맞을 때만
create or replace function public.update_song(p_id uuid, p_token uuid, p_song jsonb)
returns boolean language plpgsql security definer set search_path = public as $$
begin
  update songs set
    youtube_id = p_song->>'youtube_id',
    title      = p_song->>'title',
    artist     = coalesce(p_song->>'artist', ''),
    author     = coalesce(nullif(p_song->>'author', ''), '익명'),
    lines      = p_song->'lines',
    updated_at = now()
  where id = p_id and owner_token = p_token;
  return found;
end $$;

-- 삭제: 소유 토큰이 맞을 때만
create or replace function public.delete_song(p_id uuid, p_token uuid)
returns boolean language plpgsql security definer set search_path = public as $$
begin
  delete from songs where id = p_id and owner_token = p_token;
  return found;
end $$;

-- 부른 횟수 +1
create or replace function public.bump_play(p_id uuid)
returns void language sql security definer set search_path = public as $$
  update songs set plays = plays + 1 where id = p_id;
$$;

revoke all on function public.update_song(uuid, uuid, jsonb) from public;
revoke all on function public.delete_song(uuid, uuid) from public;
revoke all on function public.bump_play(uuid) from public;
grant execute on function public.update_song(uuid, uuid, jsonb) to anon, authenticated;
grant execute on function public.delete_song(uuid, uuid) to anon, authenticated;
grant execute on function public.bump_play(uuid) to anon, authenticated;
