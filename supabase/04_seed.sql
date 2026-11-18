-- =====================================================================
-- CAMPUS COUPON  |  04_seed.sql   Test data matching the Figma screens
-- Run AFTER you have registered at least one admin through the web
-- portal (or Dashboard -> Authentication -> Add user, with metadata
-- {"role":"admin","full_name":"Admin User","staff_number":"987654"}).
-- =====================================================================

-- Coupons from the "Coupons / Wallet" screen
insert into public.coupons (title, category, points_cost, valid_until, location, terms) values
 ('CUT T-Shirt',        'Retail', 500, '2026-12-31', 'CUT Welkom Campus Student Centre',
  E'-Valid at CUT WELKOM ONLY\n-Present student card\n-Not valid with other promotions'),
 ('Cafeteria Platter',  'Food',   300, '2026-12-31', 'CUT Welkom Campus Cafeteria',
  E'-Valid at CUT WELKOM ONLY\n-Present student card\n-Not valid with other promotions'),
 ('Skhambane / Kota',   'Food',   250, '2026-12-31', 'CUT Welkom Campus Cafeteria',
  E'-Valid at CUT WELKOM ONLY\n-Present student card\n-Not valid with other promotions');

-- Events from the "Events" / "View Event" screens (owned by the first admin).
-- Dates moved into the future so you can RSVP while testing.
insert into public.events (admin_user_id, title, description, event_date, start_time, end_time,
                           location, points_reward, category, status)
select a.event_admin_id, v.title, v.descr, v.d::date, v.s::time, v.e::time, v.loc, v.pts, v.cat, 'published'
from (select event_admin_id from public.event_administrators order by created_at limit 1) a,
(values
 ('Heritage Day',
  'As we embrace our diverse roots, let us continue to build a unified community rooted in mutual respect and shared excellence.',
  '2026-11-23', '10:00', '13:30', 'CUT Welkom Campus Hall', 100, 'Other'),
 ('Student Wellness Day',
  'A day of health screenings, mental-wellness talks and activities for all students.',
  '2026-11-06', '09:00', '14:00', 'Sports Field', 80, 'Other'),
 ('Inter Campus Soccer',
  'Support CUT Welkom against CUT Bloemfontein.',
  '2026-11-01', '15:00', '17:00', 'CUT Soccer Field', 50, 'Other'),
 ('Campus Innovation Workshop',
  'Join us for an interactive workshop on innovation, technology and problem solving. Learn from the industry experts and gain practical skills to prepare for the future.',
  '2026-11-20', '10:00', '12:00', 'Multipurpose Hall', 50, 'Career')
) as v(title, descr, d, s, e, loc, pts, cat);

-- Cafeteria staff: register in the web portal (Account type = Cafeteria Staff,
-- needs 06_cafeteria_staff.sql). Or create the user in
-- Dashboard -> Authentication -> Add user, then:
-- insert into public.cafeteria_staff (cafeteria_staff_id, name, email)
-- select id, 'Cafeteria Cashier', email from auth.users where email = 'cafeteria@cut.ac.za';
