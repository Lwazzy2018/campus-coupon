-- =====================================================================
-- CAMPUS COUPON  |  SETUP_ALL.sql   (one paste = whole database)
--
--   !!  Starts by WIPING the old Campus Coupon database, including every
--   !!  login in Authentication -> Users (see 00_reset.sql). Cannot be undone.
--
-- Contents, in order: 00_reset, 01_schema, 02_functions, 03_rls,
--                     05_storage, 06_cafeteria_staff, 07_meals
-- After it finishes: register an admin in the web portal, confirm the
-- email, then run 04_seed.sql for the test events and coupons.
-- =====================================================================


-- #####################################################################
-- ##### 00_reset.sql
-- #####################################################################
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


-- #####################################################################
-- ##### 01_schema.sql
-- #####################################################################
-- =====================================================================
-- CAMPUS COUPON  |  01_schema.sql
-- Built from: "Campus Coupon ERD Diagram" (Phase 2)
-- Run in: Supabase Dashboard -> SQL Editor (run files 01 -> 05 in order)
--
-- Every ERD entity is a table below, using the same names in snake_case.
-- Columns marked  -- [screen]  are NOT on the ERD but are needed by the
-- approved Figma screens (e.g. Create Event needs description, time,
-- points). Update the ERD to include them so design and code stay aligned.
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- STUDENTS  (ERD: PK StudentID, Name, Email)
-- student_id = the Supabase Auth user id, so login identity == student row
-- ---------------------------------------------------------------------
create table public.students (
    student_id      uuid primary key references auth.users(id) on delete cascade,
    name            text not null,
    email           text not null unique,
    student_number  text not null unique,          -- [screen] Registration / Profile
    course          text,                          -- [screen] Registration / Profile
    phone           text,                          -- [screen] Profile
    created_at      timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- WALLET  (ERD: PK WalletID, FK StudentID, Balance)   Student 1 -- 0..1 Wallet
-- ---------------------------------------------------------------------
create table public.wallet (
    wallet_id   bigint generated always as identity primary key,
    student_id  uuid not null unique references public.students(student_id) on delete cascade,
    balance     integer not null default 0 check (balance >= 0),   -- FR-018: never negative
    updated_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- EVENT ADMINISTRATOR  (ERD: PK EventAdminID, Name, Email)
-- ---------------------------------------------------------------------
create table public.event_administrators (
    event_admin_id  uuid primary key references auth.users(id) on delete cascade,
    name            text not null,
    email           text not null unique,
    staff_number    text unique,                   -- [screen] Create Admin Account
    department      text,                          -- [screen] Create Admin Account / Edit Profile
    phone           text,                          -- [screen] Edit Profile
    created_at      timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- CAFETERIA STAFF  (ERD: PK CafeteriaStaffID, Name, Email)
-- ---------------------------------------------------------------------
create table public.cafeteria_staff (
    cafeteria_staff_id  uuid primary key references auth.users(id) on delete cascade,
    name                text not null,
    email               text not null unique,
    created_at          timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- EVENTS  (ERD: PK EventID, FK AdminUserID, Title, EventDate, Location)
-- EventAdministrator 1 -- many Events
-- ---------------------------------------------------------------------
create type public.event_status as enum ('draft', 'published', 'closed');

create table public.events (
    event_id        bigint generated always as identity primary key,
    admin_user_id   uuid not null references public.event_administrators(event_admin_id),
    title           text not null check (length(trim(title)) > 0),
    description     text not null default '',      -- [screen] Create Event / Event Details
    event_date      date not null,
    start_time      time not null,                 -- [screen] "10:00 - 13:30"
    end_time        time,                          -- [screen]
    location        text not null,
    points_reward   integer not null default 0 check (points_reward >= 0),  -- [screen] Points Reward
    category        text not null default 'Other', -- [screen] filter chips All / Career / Other
    image_url       text,                          -- [screen] event poster (Supabase Storage)
    status          public.event_status not null default 'published',       -- FR-005, FR-023
    created_at      timestamptz not null default now(),
    updated_at      timestamptz not null default now(),
    check (end_time is null or end_time > start_time)
);
create index on public.events (event_date);

-- ---------------------------------------------------------------------
-- RSVP  (ERD: PK RSVPID, FK StudentID, FK EventID, Status)
-- Student 1 -- many RSVP ; Event 1 -- many RSVP
-- ---------------------------------------------------------------------
create table public.rsvp (
    rsvp_id     bigint generated always as identity primary key,
    student_id  uuid   not null references public.students(student_id) on delete cascade,
    event_id    bigint not null references public.events(event_id) on delete cascade,
    status      text   not null default 'registered' check (status in ('registered', 'cancelled')),
    created_at  timestamptz not null default now(),
    unique (student_id, event_id)                  -- FR-009: no duplicate RSVPs
);

-- ---------------------------------------------------------------------
-- ATTENDANCE  (ERD: PK AttendanceID, FK RSVPID, AttendanceStatus)
-- RSVP 1 -- 0..1 Attendance
-- ---------------------------------------------------------------------
create table public.attendance (
    attendance_id      bigint generated always as identity primary key,
    rsvp_id            bigint not null unique references public.rsvp(rsvp_id) on delete cascade,
    attendance_status  text   not null check (attendance_status in ('attended', 'not_attended')),
    verified_by        uuid   not null references public.event_administrators(event_admin_id), -- FR-011 / FR-019
    verified_at        timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- COUPONS  (catalogue shown on the "Coupons / Wallet" screen:
--           CUT T-Shirt 500, Cafeteria Platter 300, Skhambane/Kota 250)
-- Not on the ERD - ADD IT. Without it there is nothing to redeem.
-- ---------------------------------------------------------------------
create table public.coupons (
    coupon_id     bigint generated always as identity primary key,
    title         text    not null,
    category      text    not null default 'Food' check (category in ('Food', 'Retail')),
    points_cost   integer not null check (points_cost > 0),
    valid_until   date    not null,
    location      text    not null default 'CUT Welkom Campus Cafeteria',
    terms         text    not null default '',
    image_url     text,
    is_active     boolean not null default true,
    created_at    timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- REWARD TRANSACTIONS  (ERD: PK RewardTxnID, FK StudentID, FK AttendanceID, Points)
-- Attendance 1 -- 0..1 RewardTransaction   (=> unique attendance_id = "credited exactly once", FR-013)
-- Earn rows: +points, attendance_id set.  Redeem rows: -points, attendance_id null.
-- Wallet balance == SUM(points)  (FR-015)
-- ---------------------------------------------------------------------
create table public.reward_transactions (
    reward_txn_id  bigint generated always as identity primary key,
    student_id     uuid   not null references public.students(student_id) on delete cascade,
    attendance_id  bigint unique references public.attendance(attendance_id),
    txn_type       text   not null check (txn_type in ('earn', 'redeem')),
    points         integer not null check (points <> 0),
    description    text   not null default '',
    created_at     timestamptz not null default now(),
    check ((txn_type = 'earn'   and points > 0 and attendance_id is not null)
        or (txn_type = 'redeem' and points < 0 and attendance_id is null))
);
create index on public.reward_transactions (student_id, created_at desc);

-- ---------------------------------------------------------------------
-- REDEMPTIONS  (ERD: PK RedemptionID, FK StudentID, FK RewardTxnID,
--               FK CafeteriaStaffID, Status)
-- reward_txn_id -> the negative 'redeem' transaction that paid for it
-- ---------------------------------------------------------------------
create table public.redemptions (
    redemption_id       bigint generated always as identity primary key,
    student_id          uuid   not null references public.students(student_id) on delete cascade,
    reward_txn_id       bigint not null unique references public.reward_transactions(reward_txn_id),
    coupon_id           bigint not null references public.coupons(coupon_id),
    cafeteria_staff_id  uuid   references public.cafeteria_staff(cafeteria_staff_id), -- set when staff accepts
    redemption_code     text   not null unique,     -- [screen] "CC2026-7843-2219" + QR
    status              text   not null default 'issued' check (status in ('issued', 'accepted')),
    created_at          timestamptz not null default now(),
    accepted_at         timestamptz
);

-- ---------------------------------------------------------------------
-- AUDIT LOG  (FR-019 / NFR-012) - also feeds "Recent Activity" on both dashboards
-- ---------------------------------------------------------------------
create table public.audit_log (
    log_id      bigint generated always as identity primary key,
    actor_id    uuid,
    action      text not null,     -- e.g. 'event_created', 'points_redeemed', 'student_registered'
    title       text not null,     -- "New events created"
    detail      text not null default '',  -- "Campus Innovation Workshop"
    student_id  uuid,              -- lets a student see their own activity
    created_at  timestamptz not null default now()
);
create index on public.audit_log (created_at desc);

-- ---------------------------------------------------------------------
-- ADMIN NOTIFICATION PREFERENCES  ("Notification Settings" web screen)
-- ---------------------------------------------------------------------
create table public.admin_notification_prefs (
    event_admin_id          uuid primary key references public.event_administrators(event_admin_id) on delete cascade,
    new_event_registration  boolean not null default true,
    attendance_updates      boolean not null default true,
    points_redemptions      boolean not null default true,
    system_announcements    boolean not null default true,
    weekly_reports          boolean not null default false
);


-- #####################################################################
-- ##### 02_functions.sql
-- #####################################################################
-- =====================================================================
-- CAMPUS COUPON  |  02_functions.sql
-- Business rules from the SRS, enforced INSIDE the database so the
-- Flutter app and the ASP.NET portal can never disagree.
--   * Use case "Authenticate User <<include>> Role based access control"
--   * Use case "RSVP to event <<include>> Validate RSVP"
--   * Use case "Record attendance <<include>> Verify attendance
--                <<extend>> Credit reward points [Attendance = Attended]"
--   * Use case "Redeem coupon <<include>> Validate coupon balance"
--   * Use case "Accept coupon redemption" (Cafeteria staff)
-- All functions are SECURITY DEFINER: callers cannot write the tables
-- directly (see 03_rls.sql); they must go through these rules.
-- =====================================================================

-- ---------- Role-based access control helpers --------------------------
create or replace function public.is_student() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from students where student_id = auth.uid());
$$;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from event_administrators where event_admin_id = auth.uid());
$$;

create or replace function public.is_cafeteria_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from cafeteria_staff where cafeteria_staff_id = auth.uid());
$$;

-- Returns 'student' | 'admin' | 'cafeteria' | null. Both apps call this after login.
create or replace function public.current_app_role() returns text
language sql stable security definer set search_path = public as $$
  select case
    when exists (select 1 from event_administrators where event_admin_id = auth.uid()) then 'admin'
    when exists (select 1 from cafeteria_staff      where cafeteria_staff_id = auth.uid()) then 'cafeteria'
    when exists (select 1 from students             where student_id = auth.uid()) then 'student'
  end;
$$;

-- Login with "Student Number or Email" (mobile Login screen)
create or replace function public.login_email(identifier text) returns text
language sql stable security definer set search_path = public as $$
  select case when position('@' in identifier) > 0 then lower(trim(identifier))
              else (select email from students where student_number = trim(identifier)) end;
$$;

-- Login with "Staff number or email" (web Welcome Page)
create or replace function public.admin_login_email(identifier text) returns text
language sql stable security definer set search_path = public as $$
  select case when position('@' in identifier) > 0 then lower(trim(identifier))
              else (select email from event_administrators where staff_number = trim(identifier)) end;
$$;

-- ---------- Registration (Sequence 1 & 2, steps 1-3) --------------------
-- Supabase Auth creates auth.users; this trigger creates the matching
-- ERD row using the metadata the app sent with signUp().
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  meta  jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  role_ text  := coalesce(meta->>'role', 'student');
begin
  if role_ = 'admin' then
    -- Only CUT staff addresses may become administrators
    if lower(new.email) not like '%@cut.ac.za' then
      raise exception 'Administrator accounts require a @cut.ac.za email address';
    end if;
    insert into event_administrators (event_admin_id, name, email, staff_number, department)
    values (new.id, coalesce(meta->>'full_name', ''), lower(new.email),
            nullif(meta->>'staff_number', ''), nullif(meta->>'department', ''));
    insert into admin_notification_prefs (event_admin_id) values (new.id);

  elsif role_ = 'student' then
    if coalesce(meta->>'student_number', '') !~ '^[0-9]{9}$' then
      raise exception 'Student number must be 9 digits (e.g. 220123456)';
    end if;
    insert into students (student_id, name, email, student_number, course)
    values (new.id, coalesce(meta->>'full_name', ''), lower(new.email),
            meta->>'student_number', nullif(meta->>'course', ''));
    insert into wallet (student_id) values (new.id);       -- Student 1 -- 0..1 Wallet
    insert into audit_log (actor_id, action, title, detail, student_id)
    values (new.id, 'student_registered', 'New Student Registration',
            'Student: ' || (meta->>'student_number'), new.id);
  end if;
  -- 'cafeteria' (or anything else): no self-registration. Staff rows are
  -- added by IT with an INSERT into cafeteria_staff (see 04_seed.sql).
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- RSVP to event  <<include>> Validate RSVP --------------------
-- Sequence 1, steps 13-16
create or replace function public.rsvp_to_event(p_event_id bigint) returns bigint
language plpgsql security definer set search_path = public as $$
declare
  ev       events;
  v_rsvp   bigint;
begin
  if not is_student() then raise exception 'Only students can RSVP'; end if;

  select * into ev from events where event_id = p_event_id;
  if not found               then raise exception 'Event not found'; end if;
  if ev.status <> 'published' then raise exception 'This event is not open for RSVP'; end if;   -- FR-023
  if ev.event_date < current_date then raise exception 'This event has already taken place'; end if;

  insert into rsvp (student_id, event_id, status)
  values (auth.uid(), p_event_id, 'registered')
  on conflict (student_id, event_id) do update set status = 'registered'  -- FR-009: re-activate, never duplicate
  returning rsvp_id into v_rsvp;
  return v_rsvp;
end;
$$;

create or replace function public.cancel_rsvp(p_event_id bigint) returns void
language plpgsql security definer set search_path = public as $$
begin
  update rsvp set status = 'cancelled'
   where student_id = auth.uid() and event_id = p_event_id
     and not exists (select 1 from attendance a where a.rsvp_id = rsvp.rsvp_id);
end;
$$;

-- ---------- Record attendance <<include>> Verify attendance -------------
--            <<extend>> Credit reward points [Attendance = Attended]
-- Sequence 2, steps 17-22
create or replace function public.record_attendance(p_rsvp_id bigint, p_attended boolean)
returns integer   -- points credited by this call (0 if none)
language plpgsql security definer set search_path = public as $$
declare
  r         rsvp;
  ev        events;
  v_att_id  bigint;
  v_prev    text;
  v_points  integer := 0;
begin
  if not is_admin() then raise exception 'Only an authorised administrator can record attendance'; end if; -- FR-012

  select * into r from rsvp where rsvp_id = p_rsvp_id for update;
  if not found then raise exception 'RSVP not found'; end if;
  if r.status <> 'registered' then raise exception 'This RSVP was cancelled'; end if;
  select * into ev from events where event_id = r.event_id;

  select attendance_id, attendance_status into v_att_id, v_prev from attendance where rsvp_id = p_rsvp_id;

  if v_prev = 'attended' and not p_attended
     and exists (select 1 from reward_transactions where attendance_id = v_att_id) then
    raise exception 'Points were already credited for this attendance and cannot be reversed here';
  end if;

  insert into attendance (rsvp_id, attendance_status, verified_by)
  values (p_rsvp_id, case when p_attended then 'attended' else 'not_attended' end, auth.uid())
  on conflict (rsvp_id) do update
     set attendance_status = excluded.attendance_status,
         verified_by = excluded.verified_by, verified_at = now()
  returning attendance_id into v_att_id;

  -- <<extend>> only when attended (FR-014), and only once (FR-013 / NFR-006)
  if p_attended and ev.points_reward > 0
     and not exists (select 1 from reward_transactions where attendance_id = v_att_id) then
    insert into reward_transactions (student_id, attendance_id, txn_type, points, description)
    values (r.student_id, v_att_id, 'earn', ev.points_reward, 'Attended: ' || ev.title);
    update wallet set balance = balance + ev.points_reward, updated_at = now()
     where student_id = r.student_id;
    v_points := ev.points_reward;
  end if;

  insert into audit_log (actor_id, action, title, detail, student_id)
  values (auth.uid(), 'attendance_recorded',
          case when p_attended then 'Attendance approved' else 'Marked not attended' end,
          ev.title || case when v_points > 0 then ' (+' || v_points || ' points)' else '' end,
          r.student_id);
  return v_points;
end;
$$;

-- ---------- Redeem coupon <<include>> Validate coupon balance -----------
-- Mobile: Redeem Coupons -> Coupon Redeemed (QR + code)
create or replace function public.redeem_coupon(p_coupon_id bigint)
returns table (redemption_id bigint, redemption_code text, new_balance integer)
language plpgsql security definer set search_path = public as $$
declare
  c        coupons;
  v_bal    integer;
  v_txn    bigint;
  v_code   text;
  v_red    bigint;
begin
  if not is_student() then raise exception 'Only students can redeem coupons'; end if;

  select * into c from coupons where coupon_id = p_coupon_id;
  if not found or not c.is_active then raise exception 'Coupon not available'; end if;
  if c.valid_until < current_date  then raise exception 'This coupon has expired'; end if;

  -- lock the wallet row so two taps cannot spend the same points twice
  select balance into v_bal from wallet where student_id = auth.uid() for update;
  if v_bal is null or v_bal < c.points_cost then
    raise exception 'Insufficient points: you have %, this coupon needs %', coalesce(v_bal,0), c.points_cost; -- FR-018
  end if;

  insert into reward_transactions (student_id, txn_type, points, description)
  values (auth.uid(), 'redeem', -c.points_cost, 'Redeemed: ' || c.title)
  returning reward_txn_id into v_txn;

  update wallet set balance = balance - c.points_cost, updated_at = now()
   where student_id = auth.uid() returning balance into v_bal;

  loop  -- format CC2026-7843-2219, retry on the (rare) collision
    v_code := 'CC' || to_char(now(), 'YYYY') || '-' || lpad((floor(random()*10000))::int::text, 4, '0')
              || '-' || lpad((floor(random()*10000))::int::text, 4, '0');
    exit when not exists (select 1 from redemptions r where r.redemption_code = v_code);
  end loop;

  insert into redemptions (student_id, reward_txn_id, coupon_id, redemption_code)
  values (auth.uid(), v_txn, p_coupon_id, v_code)
  returning redemptions.redemption_id into v_red;

  insert into audit_log (actor_id, action, title, detail, student_id)
  values (auth.uid(), 'points_redeemed', c.points_cost || ' Points Redeemed', c.title, auth.uid());

  return query select v_red, v_code, v_bal;
end;
$$;

-- ---------- Accept coupon redemption (Cafeteria staff) ------------------
create or replace function public.accept_redemption(p_code text)
returns table (coupon_title text, student_name text, student_number text)
language plpgsql security definer set search_path = public as $$
declare
  r redemptions;
begin
  if not is_cafeteria_staff() then raise exception 'Only cafeteria staff can accept coupons'; end if;
  select * into r from redemptions where redemption_code = upper(trim(p_code)) for update;
  if not found then raise exception 'Invalid redemption code'; end if;
  if r.status = 'accepted' then raise exception 'This coupon was already used on %', to_char(r.accepted_at, 'DD Mon YYYY HH24:MI'); end if;

  update redemptions set status = 'accepted', cafeteria_staff_id = auth.uid(), accepted_at = now()
   where redemptions.redemption_id = r.redemption_id;

  return query
    select c.title, s.name, s.student_number
      from coupons c, students s
     where c.coupon_id = r.coupon_id and s.student_id = r.student_id;
end;
$$;

-- ---------- Event lifecycle (web "Delete Event" button) -----------------
-- An event with RSVPs is closed instead of deleted, so reward history survives.
create or replace function public.delete_or_close_event(p_event_id bigint) returns text
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'Not authorised'; end if;
  if exists (select 1 from rsvp where event_id = p_event_id) then
    update events set status = 'closed', updated_at = now() where event_id = p_event_id;
    return 'closed';
  end if;
  delete from events where event_id = p_event_id;
  return 'deleted';
end;
$$;

-- Audit trigger for event create/update (FR-019)
create or replace function public.log_event_change() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.updated_at := now();
  if tg_op = 'INSERT' then
    insert into audit_log (actor_id, action, title, detail)
    values (auth.uid(), 'event_created', 'New event created', new.title);
  elsif new.status is distinct from old.status or new.title <> old.title or new.event_date <> old.event_date then
    insert into audit_log (actor_id, action, title, detail)
    values (auth.uid(), 'event_updated', 'Event updated', new.title || ' (' || new.status || ')');
  end if;
  return new;
end;
$$;
create trigger trg_event_audit before insert or update on public.events
  for each row execute function public.log_event_change();

-- ---------- Dashboard numbers --------------------------------------------
-- Web "Good day, Admin": Total Events / Active Events / Points Redeemed (+ participants)
create or replace function public.admin_dashboard_stats()
returns table (total_events bigint, active_events bigint, points_redeemed bigint, total_participants bigint)
language sql stable security definer set search_path = public as $$
  select (select count(*) from events),
         (select count(*) from events where status = 'published' and event_date >= current_date),
         (select coalesce(-sum(points), 0) from reward_transactions where txn_type = 'redeem'),
         (select count(distinct student_id) from rsvp where status = 'registered')
  where public.is_admin();
$$;

-- Mobile Home: same 4-tile layout, student's own numbers
create or replace function public.student_home_stats()
returns table (upcoming_events bigint, my_rsvps bigint, events_attended bigint, points_redeemed bigint, balance integer)
language sql stable security definer set search_path = public as $$
  select (select count(*) from events where status = 'published' and event_date >= current_date),
         (select count(*) from rsvp where student_id = auth.uid() and status = 'registered'),
         (select count(*) from attendance a join rsvp r using (rsvp_id)
           where r.student_id = auth.uid() and a.attendance_status = 'attended'),
         (select coalesce(-sum(points), 0) from reward_transactions where student_id = auth.uid() and txn_type = 'redeem'),
         (select balance from wallet where student_id = auth.uid())
  where public.is_student();
$$;

-- Participants screen: one row per RSVP with Registered / Attended status
create or replace view public.event_participants
with (security_invoker = true) as
select r.rsvp_id, r.event_id, e.title as event_title, s.student_id, s.name as student_name,
       s.student_number, r.created_at as rsvp_at,
       coalesce(a.attendance_status, 'registered') as status
  from rsvp r
  join students s using (student_id)
  join events e using (event_id)
  left join attendance a using (rsvp_id)
 where r.status = 'registered';


-- #####################################################################
-- ##### 03_rls.sql
-- #####################################################################
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


-- #####################################################################
-- ##### 05_storage.sql
-- #####################################################################
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


-- #####################################################################
-- ##### 06_cafeteria_staff.sql
-- #####################################################################
-- =====================================================================
-- CAMPUS COUPON  |  06_cafeteria_staff.sql
-- Third user from the Use Case Diagram: CAFETERIA STAFF
--   Use case "Accept coupon redemption"  (+ SRS: "maintain or support
--   redemption records" -> redemption history)
--
-- Run ONCE in the Supabase SQL Editor, AFTER 01-05.
-- Safe on a database that already has students, events and redemptions:
-- it only adds columns/rules and replaces functions. It can be re-run.
--
-- What it adds
--   1. Cafeteria staff can register in the web portal (Account type =
--      Cafeteria Staff, @cut.ac.za email, unique staff number) and log in
--      with their staff number or email.
--   2. A redemption can now be APPROVED (meal given) or REJECTED (no meal).
--      Rejecting refunds the points to the student's wallet, with a reason.
--   3. list_redemptions() / cafeteria_stats() feed the Current Redemptions
--      and Redemption History pages.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------
alter table public.cafeteria_staff add column if not exists staff_number text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'cafeteria_staff_staff_number_key') then
    alter table public.cafeteria_staff add constraint cafeteria_staff_staff_number_key unique (staff_number);
  end if;
end $$;

-- Redemptions: issued (pending) -> accepted (approved, meal given) | rejected (no meal, refunded)
alter table public.redemptions add column if not exists processed_at  timestamptz;
alter table public.redemptions add column if not exists reject_reason text;
update public.redemptions set processed_at = accepted_at where status = 'accepted' and processed_at is null;

do $$
declare c record;
begin
  -- drop the old status rule (issued/accepted only), whatever it is called
  for c in select conname from pg_constraint
            where conrelid = 'public.redemptions'::regclass and contype = 'c'
              and pg_get_constraintdef(oid) ilike '%status%' loop
    execute format('alter table public.redemptions drop constraint %I', c.conname);
  end loop;
  -- drop the old earn/redeem rules on reward_transactions
  for c in select conname from pg_constraint
            where conrelid = 'public.reward_transactions'::regclass and contype = 'c'
              and pg_get_constraintdef(oid) ilike '%txn_type%' loop
    execute format('alter table public.reward_transactions drop constraint %I', c.conname);
  end loop;
end $$;

alter table public.redemptions add constraint redemptions_status_check
  check (status in ('issued', 'accepted', 'rejected'));

-- Wallet ledger: earn (+, from attendance) | redeem (-) | refund (+, rejected redemption)
alter table public.reward_transactions add constraint reward_transactions_txn_type_check
  check (txn_type in ('earn', 'redeem', 'refund'));
alter table public.reward_transactions add constraint reward_transactions_check
  check ((txn_type = 'earn'   and points > 0 and attendance_id is not null)
      or (txn_type = 'redeem' and points < 0 and attendance_id is null)
      or (txn_type = 'refund' and points > 0 and attendance_id is null));

create index if not exists redemptions_status_created_idx on public.redemptions (status, created_at desc);

-- ---------------------------------------------------------------------
-- 2. Registration: admins AND cafeteria staff register in the web portal
--    (same trigger as 02_functions.sql, with the cafeteria branch added)
-- ---------------------------------------------------------------------
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  meta  jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  role_ text  := coalesce(meta->>'role', 'student');
  staff text  := nullif(trim(meta->>'staff_number'), '');
begin
  if role_ in ('admin', 'cafeteria') then
    -- Only CUT staff addresses may use the web portal
    if lower(new.email) not like '%@cut.ac.za' then
      raise exception 'Staff accounts require a @cut.ac.za email address';
    end if;
    -- One staff number per person, across administrators and cafeteria staff
    if staff is not null and (exists (select 1 from event_administrators where staff_number = staff)
                           or exists (select 1 from cafeteria_staff      where staff_number = staff)) then
      raise exception 'Staff number % is already registered', staff;
    end if;
  end if;

  if role_ = 'admin' then
    insert into event_administrators (event_admin_id, name, email, staff_number, department)
    values (new.id, coalesce(meta->>'full_name', ''), lower(new.email), staff, nullif(meta->>'department', ''));
    insert into admin_notification_prefs (event_admin_id) values (new.id);

  elsif role_ = 'cafeteria' then
    insert into cafeteria_staff (cafeteria_staff_id, name, email, staff_number)
    values (new.id, coalesce(meta->>'full_name', ''), lower(new.email), staff);
    insert into audit_log (actor_id, action, title, detail)
    values (new.id, 'cafeteria_registered', 'New Cafeteria Staff', coalesce(meta->>'full_name', '') || ' (' || coalesce(staff, '-') || ')');

  elsif role_ = 'student' then
    if coalesce(meta->>'student_number', '') !~ '^[0-9]{9}$' then
      raise exception 'Student number must be 9 digits (e.g. 220123456)';
    end if;
    insert into students (student_id, name, email, student_number, course)
    values (new.id, coalesce(meta->>'full_name', ''), lower(new.email),
            meta->>'student_number', nullif(meta->>'course', ''));
    insert into wallet (student_id) values (new.id);
    insert into audit_log (actor_id, action, title, detail, student_id)
    values (new.id, 'student_registered', 'New Student Registration',
            'Student: ' || (meta->>'student_number'), new.id);
  end if;
  return new;
end;
$$;

-- "Staff number or email" on the web login now finds admins AND cafeteria staff
create or replace function public.admin_login_email(identifier text) returns text
language sql stable security definer set search_path = public as $$
  select case when position('@' in identifier) > 0 then lower(trim(identifier))
              else coalesce((select email from event_administrators where staff_number = trim(identifier)),
                            (select email from cafeteria_staff      where staff_number = trim(identifier))) end;
$$;

-- ---------------------------------------------------------------------
-- 3. Cafeteria actions (Use case: Accept coupon redemption)
-- ---------------------------------------------------------------------

-- APPROVE: valid coupon -> give the meal. Points were already deducted at redeem time.
create or replace function public.cafeteria_approve(p_redemption_id bigint)
returns table (coupon_title text, student_name text, student_number text)
language plpgsql security definer set search_path = public as $$
declare
  r redemptions;
  c coupons;
begin
  if not is_cafeteria_staff() then raise exception 'Only cafeteria staff can approve coupons'; end if;
  select * into r from redemptions where redemption_id = p_redemption_id for update;
  if not found then raise exception 'Redemption not found'; end if;
  if r.status = 'accepted' then
    raise exception 'This coupon was already approved on %', to_char(r.processed_at, 'DD Mon YYYY HH24:MI');
  end if;
  if r.status = 'rejected' then raise exception 'This coupon was rejected and its points were refunded'; end if;
  select * into c from coupons where coupon_id = r.coupon_id;
  if c.valid_until < current_date then
    raise exception 'This coupon expired on %. Reject it to refund the student''s points.', to_char(c.valid_until, 'DD Mon YYYY');
  end if;

  update redemptions
     set status = 'accepted', cafeteria_staff_id = auth.uid(), accepted_at = now(), processed_at = now()
   where redemption_id = r.redemption_id;

  insert into audit_log (actor_id, action, title, detail, student_id)
  values (auth.uid(), 'redemption_approved', 'Coupon Used', c.title || ' - meal collected', r.student_id);

  return query select c.title, s.name, s.student_number from students s where s.student_id = r.student_id;
end;
$$;

-- REJECT: no meal given -> points go back to the student's wallet (refund), with a reason.
create or replace function public.cafeteria_reject(p_redemption_id bigint, p_reason text)
returns table (coupon_title text, student_name text, student_number text, refunded_points integer)
language plpgsql security definer set search_path = public as $$
declare
  r      redemptions;
  c      coupons;
  v_cost integer;
  v_why  text := nullif(trim(coalesce(p_reason, '')), '');
begin
  if not is_cafeteria_staff() then raise exception 'Only cafeteria staff can reject coupons'; end if;
  if v_why is null then raise exception 'Select a reason for rejecting the coupon'; end if;
  select * into r from redemptions where redemption_id = p_redemption_id for update;
  if not found then raise exception 'Redemption not found'; end if;
  if r.status <> 'issued' then
    raise exception 'This coupon was already %', case r.status when 'accepted' then 'approved' else r.status end;
  end if;
  select * into c from coupons where coupon_id = r.coupon_id;

  -- refund exactly what was paid (the original redeem transaction)
  select -points into v_cost from reward_transactions where reward_txn_id = r.reward_txn_id;

  insert into reward_transactions (student_id, txn_type, points, description)
  values (r.student_id, 'refund', v_cost, 'Refund: ' || c.title || ' (rejected: ' || v_why || ')');
  update wallet set balance = balance + v_cost, updated_at = now() where student_id = r.student_id;

  update redemptions
     set status = 'rejected', cafeteria_staff_id = auth.uid(), processed_at = now(), reject_reason = v_why
   where redemption_id = r.redemption_id;

  insert into audit_log (actor_id, action, title, detail, student_id)
  values (auth.uid(), 'redemption_rejected', v_cost || ' Points Refunded', c.title || ' - ' || v_why, r.student_id);

  return query select c.title, s.name, s.student_number, v_cost from students s where s.student_id = r.student_id;
end;
$$;

-- Old "type the code" function from 02_functions.sql: now the same as Approve.
create or replace function public.accept_redemption(p_code text)
returns table (coupon_title text, student_name text, student_number text)
language plpgsql security definer set search_path = public as $$
declare v_id bigint;
begin
  if not is_cafeteria_staff() then raise exception 'Only cafeteria staff can accept coupons'; end if;
  select redemption_id into v_id from redemptions where redemption_code = upper(trim(p_code));
  if v_id is null then raise exception 'Invalid redemption code'; end if;
  return query select * from public.cafeteria_approve(v_id);
end;
$$;

-- ---------------------------------------------------------------------
-- 4. Lists and numbers for the Cafeteria pages (admins can read them too)
-- ---------------------------------------------------------------------
-- p_status: 'issued' (current/pending) | 'accepted' | 'rejected' | null = all
-- p_search: redemption code, student number or student name
create or replace function public.list_redemptions(
  p_status text default null, p_search text default null,
  p_from date default null, p_to date default null, p_limit integer default 300)
returns table (
  redemption_id bigint, redemption_code text, status text,
  coupon_title text, points_cost integer, valid_until date,
  student_name text, student_number text,
  created_at timestamptz, processed_at timestamptz, processed_by text, reject_reason text)
language sql stable security definer set search_path = public as $$
  select r.redemption_id, r.redemption_code, r.status,
         c.title, -t.points, c.valid_until,
         s.name, s.student_number,
         r.created_at, r.processed_at, cs.name, r.reject_reason
    from redemptions r
    join coupons c              on c.coupon_id = r.coupon_id
    join students s             on s.student_id = r.student_id
    join reward_transactions t  on t.reward_txn_id = r.reward_txn_id
    left join cafeteria_staff cs on cs.cafeteria_staff_id = r.cafeteria_staff_id
   where (public.is_cafeteria_staff() or public.is_admin())
     and (p_status is null or r.status = p_status)
     and (p_search is null or trim(p_search) = ''
          or r.redemption_code ilike '%' || trim(p_search) || '%'
          or s.student_number  ilike '%' || trim(p_search) || '%'
          or s.name            ilike '%' || trim(p_search) || '%')
     and (p_from is null or r.created_at >= p_from::timestamptz)
     and (p_to   is null or r.created_at <  (p_to + 1)::timestamptz)
   order by case when p_status = 'issued' then extract(epoch from r.created_at) end asc nulls last, -- queue: oldest first
            r.created_at desc
   limit greatest(1, least(coalesce(p_limit, 300), 1000));
$$;

-- Numbers across the top of the Cafeteria pages
create or replace function public.cafeteria_stats()
returns table (pending bigint, approved_today bigint, rejected_today bigint,
               approved_total bigint, rejected_total bigint, points_approved_today bigint)
language sql stable security definer set search_path = public as $$
  select count(*) filter (where r.status = 'issued'),
         count(*) filter (where r.status = 'accepted' and r.processed_at >= current_date),
         count(*) filter (where r.status = 'rejected' and r.processed_at >= current_date),
         count(*) filter (where r.status = 'accepted'),
         count(*) filter (where r.status = 'rejected'),
         coalesce(-sum(t.points) filter (where r.status = 'accepted' and r.processed_at >= current_date), 0)
    from redemptions r
    join reward_transactions t on t.reward_txn_id = r.reward_txn_id
   where public.is_cafeteria_staff() or public.is_admin();
$$;

-- ---------------------------------------------------------------------
-- 5. Security (Row Level Security + who may call what)
-- ---------------------------------------------------------------------
-- Cafeteria staff may update their own name (not email / staff number)
drop policy if exists staff_update_own on public.cafeteria_staff;
create policy staff_update_own on public.cafeteria_staff for update to authenticated
  using (cafeteria_staff_id = auth.uid()) with check (cafeteria_staff_id = auth.uid());
revoke update on public.cafeteria_staff from authenticated;
grant  update (name) on public.cafeteria_staff to authenticated;

-- Admin "Redemptions" page shows the coupon even after it is deactivated
drop policy if exists coupons_select on public.coupons;
create policy coupons_select on public.coupons for select to authenticated
  using (is_active or public.is_admin() or public.is_cafeteria_staff());

revoke execute on function public.cafeteria_approve(bigint)                         from public, anon;
revoke execute on function public.cafeteria_reject(bigint, text)                    from public, anon;
revoke execute on function public.accept_redemption(text)                           from public, anon;
revoke execute on function public.list_redemptions(text, text, date, date, integer) from public, anon;
revoke execute on function public.cafeteria_stats()                                 from public, anon;
grant  execute on function public.cafeteria_approve(bigint)                         to authenticated;
grant  execute on function public.cafeteria_reject(bigint, text)                    to authenticated;
grant  execute on function public.accept_redemption(text)                           to authenticated;
grant  execute on function public.list_redemptions(text, text, date, date, integer) to authenticated;
grant  execute on function public.cafeteria_stats()                                 to authenticated;
-- the login lookup must stay callable before sign-in
grant  execute on function public.admin_login_email(text) to anon, authenticated;
revoke execute on function public.handle_new_user() from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 6. Optional: turn an EXISTING login into a cafeteria staff account
--    (e.g. a user created in Dashboard -> Authentication -> Add user).
--    Change the email, name and staff number, remove the "--" and run.
-- ---------------------------------------------------------------------
-- insert into public.cafeteria_staff (cafeteria_staff_id, name, email, staff_number)
-- select id, 'Cafeteria Cashier', lower(email), '555001' from auth.users where email = 'cafeteria@cut.ac.za';


-- #####################################################################
-- ##### 07_meals.sql
-- #####################################################################
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
