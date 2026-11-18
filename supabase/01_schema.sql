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
