-- =====================================================================
-- CAMPUS COUPON  |  00_reset.sql
-- WIPES the Campus Coupon database so it can be rebuilt from scratch.
--
--   !!  Deletes ALL Campus Coupon data: students, admins, cafeteria staff,
--   !!  events, RSVPs, attendance, wallets, coupons, redemptions, AND every
--   !!  login in Authentication -> Users. This cannot be undone.
--
-- Keeps: the "event-media" storage bucket and any uploaded posters.
-- Safe to run more than once. Next: run SETUP_ALL.sql (or 01, 02, 03, 05, 06, 07).
-- =====================================================================

-- 1. Sign-up trigger on Supabase Auth
drop trigger if exists on_auth_user_created on auth.users;

-- 2. Storage policies from 05_storage.sql (the bucket and files stay)
do $$
begin
  if to_regclass('storage.objects') is not null then
    drop policy if exists "event media public read"  on storage.objects;
    drop policy if exists "event media admin insert" on storage.objects;
    drop policy if exists "event media admin update" on storage.objects;
    drop policy if exists "event media admin delete" on storage.objects;
    drop policy if exists "coupon images cafeteria insert" on storage.objects;
    drop policy if exists "coupon images cafeteria update" on storage.objects;
    drop policy if exists "coupon images cafeteria delete" on storage.objects;
  end if;
end $$;

-- 3. View, tables (with their policies, indexes and triggers) and the enum type
drop view if exists public.event_participants cascade;
drop table if exists
  public.admin_notification_prefs,
  public.audit_log,
  public.redemptions,
  public.reward_transactions,
  public.attendance,
  public.rsvp,
  public.events,
  public.coupons,
  public.wallet,
  public.cafeteria_staff,
  public.event_administrators,
  public.students
  cascade;
drop type if exists public.event_status cascade;

-- 4. Every Campus Coupon function (any version / argument list)
do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in (
         'is_student', 'is_admin', 'is_cafeteria_staff', 'current_app_role',
         'login_email', 'admin_login_email', 'handle_new_user',
         'rsvp_to_event', 'cancel_rsvp', 'record_attendance', 'redeem_coupon',
         'accept_redemption', 'cafeteria_approve', 'cafeteria_reject',
         'list_redemptions', 'cafeteria_stats',
         'delete_or_close_event', 'log_event_change', 'log_coupon_change',
         'admin_dashboard_stats', 'student_home_stats')
  loop
    execute format('drop function if exists %s cascade', f.sig);
  end loop;
end $$;

-- 5. All logins (Authentication -> Users). Old accounts would otherwise be
--    "half accounts" with no student/admin row, and their emails could not
--    register again.
delete from auth.users;
