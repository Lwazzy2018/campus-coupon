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
