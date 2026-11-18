-- =====================================================================
-- CAMPUS COUPON  |  05_storage.sql   Supabase Storage (architecture diagram:
-- "Storage - Event Media & Application Assets")
-- Public bucket for event posters and coupon images: anyone can view,
-- only administrators can upload/replace/delete.
-- =====================================================================
insert into storage.buckets (id, name, public)
values ('event-media', 'event-media', true)
on conflict (id) do nothing;

create policy "event media public read" on storage.objects for select
  using (bucket_id = 'event-media');

create policy "event media admin insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'event-media' and public.is_admin());

create policy "event media admin update" on storage.objects for update to authenticated
  using (bucket_id = 'event-media' and public.is_admin());

create policy "event media admin delete" on storage.objects for delete to authenticated
  using (bucket_id = 'event-media' and public.is_admin());
