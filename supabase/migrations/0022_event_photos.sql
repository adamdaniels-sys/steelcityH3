-- Steel City H3 — event photos + public attendee roster
--
--   1. event_photos table — one row per uploaded photo (metadata; the file lives
--      in Storage). Public read, admin write.
--   2. Storage bucket 'event-photos' (public) + policies: anyone can view,
--      admins can upload/replace/delete.
--   3. get_event_attendees_public(event_id) — names-only roster for a PAST event,
--      so the write-up can list who actually came (incl. legacy attendees, who
--      have no RSVP). Mirrors the hash-name / SCH3 Hash Virgin display rules.
--
-- Run in the Supabase SQL Editor AFTER 0001-0021. Idempotent.

-- ============================================================================
-- 1. event_photos
-- ============================================================================
create table if not exists public.event_photos (
  id           uuid        primary key default gen_random_uuid(),
  event_id     integer     not null references public.events(id) on delete cascade,
  storage_path text        not null,                 -- path within the 'event-photos' bucket
  caption      text,
  sort_order   integer     not null default 0,
  uploaded_by  uuid                 references public.profiles(id) on delete set null,
  created_at   timestamptz not null default now()
);
create index if not exists event_photos_event_idx on public.event_photos (event_id, sort_order, created_at);

alter table public.event_photos enable row level security;

drop policy if exists "event_photos: public read"  on public.event_photos;
drop policy if exists "event_photos: admin insert"  on public.event_photos;
drop policy if exists "event_photos: admin update"  on public.event_photos;
drop policy if exists "event_photos: admin delete"  on public.event_photos;

create policy "event_photos: public read"
  on public.event_photos for select using (true);
create policy "event_photos: admin insert"
  on public.event_photos for insert with check (public.is_admin(auth.uid()));
create policy "event_photos: admin update"
  on public.event_photos for update using (public.is_admin(auth.uid())) with check (public.is_admin(auth.uid()));
create policy "event_photos: admin delete"
  on public.event_photos for delete using (public.is_admin(auth.uid()));

grant select                         on public.event_photos to anon, authenticated;
grant insert, update, delete         on public.event_photos to authenticated;


-- ============================================================================
-- 2. Storage bucket + policies
-- ============================================================================
-- If this INSERT errors in your project, just make the bucket by hand instead:
--   Storage -> New bucket -> name "event-photos" -> Public -> Save.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('event-photos', 'event-photos', true, 10485760,
        array['image/jpeg','image/png','image/webp'])
on conflict (id) do update
  set public = true,
      file_size_limit = 10485760,
      allowed_mime_types = array['image/jpeg','image/png','image/webp'];

drop policy if exists "event photos: public read"  on storage.objects;
drop policy if exists "event photos: admin insert"  on storage.objects;
drop policy if exists "event photos: admin update"  on storage.objects;
drop policy if exists "event photos: admin delete"  on storage.objects;

create policy "event photos: public read"
  on storage.objects for select
  using (bucket_id = 'event-photos');
create policy "event photos: admin insert"
  on storage.objects for insert
  with check (bucket_id = 'event-photos' and public.is_admin(auth.uid()));
create policy "event photos: admin update"
  on storage.objects for update
  using (bucket_id = 'event-photos' and public.is_admin(auth.uid()));
create policy "event photos: admin delete"
  on storage.objects for delete
  using (bucket_id = 'event-photos' and public.is_admin(auth.uid()));


-- ============================================================================
-- 3. get_event_attendees_public — names-only roster for a PAST event
-- ============================================================================
create or replace function public.get_event_attendees_public(p_event_id integer)
returns table (
  display_name text,
  kennel_name  text,
  is_hare      boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  return query
  select
    coalesce(
      nullif(trim(p.hash_name), ''),
      nullif(trim(a.attendee_label), ''),
      case when a.user_id is not null
           then 'SCH3 Hash Virgin ' || coalesce(nullif(trim(split_part(p.real_name, ' ', 1)), ''), 'newcomer')
           else 'Hasher' end
    ) as display_name,
    case when a.user_id is not null then p.kennel_name else a.attendee_kennel end as kennel_name,
    exists (
      select 1 from public.event_hares h
      where h.event_id = a.event_id and h.user_id = a.user_id
    ) as is_hare
  from public.event_attendances a
  join public.events e on e.id = a.event_id
  left join public.profiles p on p.id = a.user_id
  where a.event_id = p_event_id
    and e.event_date < current_date
  order by
    exists (select 1 from public.event_hares h where h.event_id = a.event_id and h.user_id = a.user_id) desc,
    lower(coalesce(nullif(trim(p.hash_name), ''), a.attendee_label, ''));
end;
$$;

grant execute on function public.get_event_attendees_public(integer) to anon, authenticated;
