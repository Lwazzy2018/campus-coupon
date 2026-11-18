-- =====================================================================
-- CAMPUS COUPON  |  03_rls.sql   Row Level Security (NFR-004, NFR-005)
-- Rule of thumb:
--   * Everyone signed in can READ what their role needs.
--   * Direct WRITES are allowed only where no business rule is involved
--     (admin editing events/coupons, users editing their own profile).
--   * Wallet, RSVP, attendance, rewards, redemptions are written ONLY
--     through the functions in 02_functions.sql.
-- =====================================================================

alter table public.students                 enable row level security;
alter table public.wallet                   enable row level security;
alter table public.event_administrators     enable row level security;
alter table public.cafeteria_staff          enable row level security;
alter table public.events                   enable row level security;
alter table public.rsvp                     enable row level security;
alter table public.attendance               enable row level security;
alter table public.coupons                  enable row level security;
alter table public.reward_transactions      enable row level security;
alter table public.redemptions              enable row level security;
alter table public.audit_log                enable row level security;
alter table public.admin_notification_prefs enable row level security;

-- STUDENTS: own row (read + update profile); admins read all
create policy students_select on public.students for select to authenticated
  using (student_id = auth.uid() or public.is_admin());
create policy students_update_own on public.students for update to authenticated
  using (student_id = auth.uid()) with check (student_id = auth.uid());
-- students may not change their own student_number/email through the API:
revoke update on public.students from authenticated;
grant  update (name, course, phone) on public.students to authenticated;

-- WALLET: read own; admins read all. No direct writes.
create policy wallet_select on public.wallet for select to authenticated
  using (student_id = auth.uid() or public.is_admin());

-- EVENT ADMINISTRATORS: admins read all, update own profile
create policy admins_select on public.event_administrators for select to authenticated
  using (public.is_admin());
create policy admins_update_own on public.event_administrators for update to authenticated
  using (event_admin_id = auth.uid()) with check (event_admin_id = auth.uid());
revoke update on public.event_administrators from authenticated;
grant  update (name, department, phone, staff_number) on public.event_administrators to authenticated;

-- CAFETERIA STAFF: read own row
create policy staff_select on public.cafeteria_staff for select to authenticated
  using (cafeteria_staff_id = auth.uid() or public.is_admin());

-- EVENTS: students see published/closed; admins see & manage all
create policy events_select on public.events for select to authenticated
  using (status <> 'draft' or public.is_admin());
create policy events_insert on public.events for insert to authenticated
  with check (public.is_admin() and admin_user_id = auth.uid());
create policy events_update on public.events for update to authenticated
  using (public.is_admin()) with check (public.is_admin());
-- (no delete policy: use delete_or_close_event())

-- RSVP / ATTENDANCE: student sees own, admin sees all. Writes via functions only.
create policy rsvp_select on public.rsvp for select to authenticated
  using (student_id = auth.uid() or public.is_admin());
create policy attendance_select on public.attendance for select to authenticated
  using (public.is_admin()
         or exists (select 1 from public.rsvp r where r.rsvp_id = attendance.rsvp_id and r.student_id = auth.uid()));

-- COUPONS: everyone signed in reads active ones; admins manage
create policy coupons_select on public.coupons for select to authenticated
  using (is_active or public.is_admin());
create policy coupons_admin_write on public.coupons for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- REWARD TRANSACTIONS / REDEMPTIONS: own rows; admins + cafeteria read
create policy rtx_select on public.reward_transactions for select to authenticated
  using (student_id = auth.uid() or public.is_admin());
create policy red_select on public.redemptions for select to authenticated
  using (student_id = auth.uid() or public.is_admin() or public.is_cafeteria_staff());

-- AUDIT LOG: admins read all; students read their own lines
create policy audit_select on public.audit_log for select to authenticated
  using (public.is_admin() or student_id = auth.uid());

-- NOTIFICATION PREFS: admin reads/updates own
create policy prefs_select on public.admin_notification_prefs for select to authenticated
  using (event_admin_id = auth.uid());
create policy prefs_update on public.admin_notification_prefs for update to authenticated
  using (event_admin_id = auth.uid()) with check (event_admin_id = auth.uid());

-- Functions: anonymous users may only resolve a login identifier.
revoke execute on all functions in schema public from public, anon;
grant  execute on all functions in schema public to authenticated;
grant  execute on function public.login_email(text), public.admin_login_email(text) to anon;
revoke execute on function public.handle_new_user() from authenticated;
