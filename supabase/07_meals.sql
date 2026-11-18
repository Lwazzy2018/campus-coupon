-- =====================================================================
-- CAMPUS COUPON  |  07_meals.sql
-- "Meals" page (cafeteria staff) and "Coupons" page (event administrators)
--   Use Case Diagram: Event administrator -> "Coupon Allocation"
--   SRS: Staff/Admin "Coupon Management - create, view, update and manage coupons"
--
-- Run ONCE in the Supabase SQL Editor, AFTER 06_cafeteria_staff.sql.
-- Safe on a database that already has data. Can be re-run.
--
--   * Administrators manage ALL coupons (Food and Retail) - unchanged.
--   * Cafeteria staff manage MEALS (Food coupons) only.
--   * Both can upload a meal/coupon photo to storage (folder coupons/).
--   * Adding / changing a coupon is written to the audit log.
-- =====================================================================

-- 1. Cafeteria staff may add / edit / delete Food coupons (meals)
drop policy if exists coupons_cafeteria_write on public.coupons;
create policy coupons_cafeteria_write on public.coupons for all to authenticated
  using (public.is_cafeteria_staff() and category = 'Food')
  with check (public.is_cafeteria_staff() and category = 'Food');

-- 2. Photo uploads: cafeteria staff may write in event-media/coupons/
--    (administrators can already upload anywhere in event-media, 05_storage.sql)
do $$
begin
  if to_regclass('storage.objects') is not null then
    drop policy if exists "coupon images cafeteria insert" on storage.objects;
    drop policy if exists "coupon images cafeteria update" on storage.objects;
    drop policy if exists "coupon images cafeteria delete" on storage.objects;
    create policy "coupon images cafeteria insert" on storage.objects for insert to authenticated
      with check (bucket_id = 'event-media' and name like 'coupons/%' and public.is_cafeteria_staff());
    create policy "coupon images cafeteria update" on storage.objects for update to authenticated
      using (bucket_id = 'event-media' and name like 'coupons/%' and public.is_cafeteria_staff());
    create policy "coupon images cafeteria delete" on storage.objects for delete to authenticated
      using (bucket_id = 'event-media' and name like 'coupons/%' and public.is_cafeteria_staff());
  end if;
end $$;

-- 3. Audit log ("Recent Activity" on the admin dashboard)
create or replace function public.log_coupon_change() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    insert into audit_log (actor_id, action, title, detail)
    values (auth.uid(), 'coupon_created', 'New ' || case when new.category = 'Food' then 'meal' else 'coupon' end || ' added',
            new.title || ' (' || new.points_cost || ' points)');
  elsif new.is_active is distinct from old.is_active then
    insert into audit_log (actor_id, action, title, detail)
    values (auth.uid(), 'coupon_updated',
            case when new.is_active then 'Coupon switched on' else 'Coupon switched off' end, new.title);
  elsif new.points_cost <> old.points_cost or new.title <> old.title or new.valid_until <> old.valid_until then
    insert into audit_log (actor_id, action, title, detail)
    values (auth.uid(), 'coupon_updated', 'Coupon updated', new.title || ' (' || new.points_cost || ' points)');
  end if;
  return new;
end;
$$;
revoke execute on function public.log_coupon_change() from public, anon, authenticated;

drop trigger if exists trg_coupon_audit on public.coupons;
create trigger trg_coupon_audit after insert or update on public.coupons
  for each row execute function public.log_coupon_change();
