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
