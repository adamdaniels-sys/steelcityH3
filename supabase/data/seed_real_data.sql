-- Steel City H3 - REAL DATA seed (generated from 'ROUND UP.ods')
-- Run AFTER clear_test_data.sql and AFTER migrations 0001-0020.
--
-- Every attendee is loaded as a LEGACY attendee (no account yet). When the real
-- person signs up with the same hash name, merge them on the Legacy attendees
-- page to fold their history into their account (incl. the 3 admins).
-- Fees mirror the sheet: 3.00 standard, 0 for hares & SCH3 Hash Virgins
-- ('First timer'). 'owes' = unpaid (a debt). Charity OFF - the 3 pounds is club funds.

do $$ begin
  if not exists (select 1 from information_schema.columns
                 where table_name='event_attendances' and column_name='is_legacy')
  then raise exception 'Run migrations 0018 + 0019 + 0020 first.'; end if;
end $$;

begin;
set local app.suppress_audit = 'on';

-- ===== Run 3 - April 2025 Hash - Travellers Rest, Hope =====
insert into public.events (id, run_number, title, event_date, start_time, location_summary, event_type, amount_per_head, is_charity_event, status, hares, written_up, attendance_finalised_at)
  values (3, 3, 'April 2025 Hash', '2025-04-26', '12:00', 'Travellers Rest, Hope', 'hash', 3.00, false, 'completed', 'Tweeny', false, '2025-04-26 12:00');
insert into public.event_attendances (event_id, attendee_label, attendee_kennel, is_legacy, amount_paid, paid) values
  (3, 'Flying Bottom', null, true, 3.00, true),
  (3, 'Rab C', null, true, 3.00, true),
  (3, 'Wheelchair', null, true, 3.00, true),
  (3, 'Horse''s Arse', null, true, 3.00, true),
  (3, 'Dipstick', null, true, 3.00, true),
  (3, 'Belly Dancer', null, true, 3.00, true),
  (3, 'Smutley', null, true, 3.00, true),
  (3, 'Queen Myrtle', null, true, 3.00, true),
  (3, 'Check Me Out', null, true, 0.00, true)  /* first timer */,
  (3, 'Gaggin Ferrit', null, true, 3.00, true)  /* first timer */,
  (3, 'Tweeny', null, true, 0.00, true)  /* hare */;

-- ===== Run 4 - May 2025 Hash - Old Queens Head =====
insert into public.events (id, run_number, title, event_date, start_time, location_summary, event_type, amount_per_head, is_charity_event, status, hares, written_up, attendance_finalised_at)
  values (4, 4, 'May 2025 Hash', '2025-05-24', '12:00', 'Old Queens Head', 'hash', 3.00, false, 'completed', 'Smutley, Queen Myrtle', false, '2025-05-24 12:00');
insert into public.event_attendances (event_id, attendee_label, attendee_kennel, is_legacy, amount_paid, paid) values
  (4, 'Flying Bottom', null, true, 3.00, true),
  (4, 'Wheelchair', null, true, 3.00, true),
  (4, 'Diarrhoea', null, true, 3.00, true),
  (4, 'Baritone', null, true, 3.00, true),
  (4, 'Belly Dancer', null, true, 3.00, true),
  (4, 'Nate', null, true, 0.00, true)  /* first timer, UNMAPPED:Fl */,
  (4, 'Seb', null, true, 0.00, true)  /* first timer */,
  (4, 'Smutley', null, true, 0.00, true)  /* hare */,
  (4, 'Queen Myrtle', null, true, 0.00, true)  /* hare */;

-- ===== Run 5 - June 2025 Hash - Dore & Totley Station =====
insert into public.events (id, run_number, title, event_date, start_time, location_summary, event_type, amount_per_head, is_charity_event, status, hares, written_up, attendance_finalised_at)
  values (5, 5, 'June 2025 Hash', '2025-06-28', '12:00', 'Dore & Totley Station', 'hash', 3.00, false, 'completed', 'Queen Myrtle, Smutley', false, '2025-06-28 12:00');
insert into public.event_attendances (event_id, attendee_label, attendee_kennel, is_legacy, amount_paid, paid) values
  (5, 'Flying Bottom', null, true, 3.00, true),
  (5, 'Wheelchair', null, true, 3.00, true),
  (5, 'Horny Devil', null, true, 0.00, true),
  (5, 'Horse''s Arse', null, true, 3.00, true),
  (5, 'Fishy Red', null, true, 3.00, true),
  (5, 'Rab C', null, true, 3.00, true),
  (5, 'Belly Dancer', null, true, 3.00, true)  /* RA */,
  (5, 'Gaggin Ferrit', null, true, 3.00, true),
  (5, 'Queen Myrtle', null, true, 0.00, true)  /* hare */,
  (5, 'Smutley', null, true, 0.00, true)  /* hare */;

-- ===== Run 6 - July 2025 Hash - Wheatsheaf, Baslow =====
insert into public.events (id, run_number, title, event_date, start_time, location_summary, event_type, amount_per_head, is_charity_event, status, hares, written_up, attendance_finalised_at)
  values (6, 6, 'July 2025 Hash', '2025-07-26', '12:00', 'Wheatsheaf, Baslow', 'hash', 3.00, false, 'completed', 'Flying Bottom, Wheelchair', false, '2025-07-26 12:00');
insert into public.event_attendances (event_id, attendee_label, attendee_kennel, is_legacy, amount_paid, paid) values
  (6, 'Flying Bottom', null, true, 0.00, true)  /* hare */,
  (6, 'Wheelchair', null, true, 0.00, true)  /* hare */,
  (6, 'Footloose', 'Yorkshire H3', true, 0.00, true)  /* first timer */,
  (6, 'HRT', 'Yorkshire H3', true, 0.00, true)  /* first timer */,
  (6, 'Crooked Squire', 'Quorn', true, 3.00, true),
  (6, 'Ale B Off', 'Bull Moon', true, 0.00, true)  /* first timer */,
  (6, 'Knock Out', 'Chiang Mai', true, 0.00, true)  /* first timer */,
  (6, 'Prison Bitch', null, true, 0.00, true),
  (6, 'Discharge', null, true, 0.00, true),
  (6, 'Mr Poo', null, true, 0.00, true),
  (6, 'Rab C', null, true, 3.00, true),
  (6, 'Queen Myrtle', null, true, 3.00, true),
  (6, 'Smutley', null, true, 3.00, true);

-- ===== Run 7 - August 2025 Hash - The Angel, Woodhouse =====
insert into public.events (id, run_number, title, event_date, start_time, location_summary, event_type, amount_per_head, is_charity_event, status, hares, written_up, attendance_finalised_at)
  values (7, 7, 'August 2025 Hash', '2025-08-30', '12:00', 'The Angel, Woodhouse', 'hash', 3.00, false, 'completed', 'Smutley, Queen Myrtle', false, '2025-08-30 12:00');
insert into public.event_attendances (event_id, attendee_label, attendee_kennel, is_legacy, amount_paid, paid) values
  (7, 'Smutley', null, true, 0.00, true)  /* hare */,
  (7, 'Queen Myrtle', null, true, 0.00, true)  /* hare */,
  (7, 'Footloose', 'Yorkshire H3', true, 3.00, true),
  (7, 'Rab C', null, true, 3.00, true),
  (7, 'Tweeny', null, true, 3.00, true),
  (7, 'Flying Bottom', null, true, 3.00, true),
  (7, 'Wheelchair', null, true, 3.00, true),
  (7, 'HRT', 'Yorkshire H3', true, 3.00, true),
  (7, 'Just Sue', null, true, 0.00, true)  /* first timer */;

-- ===== Run 8 - September 2025 Hash - Scarsdale 100, Drakehouse =====
insert into public.events (id, run_number, title, event_date, start_time, location_summary, event_type, amount_per_head, is_charity_event, status, hares, written_up, attendance_finalised_at)
  values (8, 8, 'September 2025 Hash', '2025-09-27', '12:00', 'Scarsdale 100, Drakehouse', 'hash', 3.00, false, 'completed', 'Smutley', false, '2025-09-27 12:00');
insert into public.event_attendances (event_id, attendee_label, attendee_kennel, is_legacy, amount_paid, paid) values
  (8, 'Smutley', null, true, 0.00, true)  /* hare */,
  (8, 'Diarrhoea', 'Quorn', true, 3.00, true),
  (8, 'Vibrator', null, true, 0.00, true)  /* first timer */,
  (8, 'Ice Delight', null, true, 0.00, true)  /* first timer */,
  (8, 'Flying Bottom', null, true, 3.00, true),
  (8, 'Wheelchair', null, true, 3.00, true);

-- Run 9: no data in the spreadsheet - skipped.

-- Run 10: no data in the spreadsheet - skipped.

-- ===== Run 11 - December 2025 Hash - Old Queens Head =====
insert into public.events (id, run_number, title, event_date, start_time, location_summary, event_type, amount_per_head, is_charity_event, status, hares, written_up, attendance_finalised_at)
  values (11, 11, 'December 2025 Hash', '2025-12-13', '12:00', 'Old Queens Head', 'hash', 3.00, false, 'completed', 'Smutley, Queen Myrtle', false, '2025-12-13 12:00');
insert into public.event_attendances (event_id, attendee_label, attendee_kennel, is_legacy, amount_paid, paid) values
  (11, 'Smutley', null, true, 0.00, true)  /* hare */,
  (11, 'Queen Myrtle', null, true, 0.00, true)  /* hare */,
  (11, 'Flying Bottom', null, true, 3.00, true),
  (11, 'Wheelchair', null, true, 3.00, true),
  (11, 'Baritone', 'Quorn', true, 3.00, true),
  (11, 'Diarrhoea', 'Quorn', true, 3.00, true),
  (11, 'Mug Plug', 'Rutland', true, 3.00, true);

-- ===== Run 12 - January 2026 Hash - New York, Rotherham =====
insert into public.events (id, run_number, title, event_date, start_time, location_summary, event_type, amount_per_head, is_charity_event, status, hares, written_up, attendance_finalised_at)
  values (12, 12, 'January 2026 Hash', '2026-01-17', '12:00', 'New York, Rotherham', 'hash', 3.00, false, 'completed', 'Smutley, Queen Myrtle', false, '2026-01-17 12:00');
insert into public.event_attendances (event_id, attendee_label, attendee_kennel, is_legacy, amount_paid, paid) values
  (12, 'Smutley', null, true, 0.00, true)  /* hare */,
  (12, 'Queen Myrtle', null, true, 0.00, true)  /* hare */,
  (12, 'Tweeny', null, true, 3.00, true),
  (12, 'Flying Bottom', null, true, 3.00, true),
  (12, 'Wheelchair', null, true, 3.00, true);

-- ===== Run 13 - February 2026 Hash - Castle Inn, Bakewell =====
insert into public.events (id, run_number, title, event_date, start_time, location_summary, event_type, amount_per_head, is_charity_event, status, hares, written_up, attendance_finalised_at)
  values (13, 13, 'February 2026 Hash', '2026-02-21', '12:00', 'Castle Inn, Bakewell', 'hash', 3.00, false, 'completed', 'Flying Bottom, Wheelchair', false, '2026-02-21 12:00');
insert into public.event_attendances (event_id, attendee_label, attendee_kennel, is_legacy, amount_paid, paid) values
  (13, 'Flying Bottom', null, true, 0.00, true)  /* hare */,
  (13, 'Wheelchair', null, true, 0.00, true)  /* hare */,
  (13, 'Horse''s Arse', null, true, 3.00, false),
  (13, 'Malteser', null, true, 0.00, true)  /* first timer */,
  (13, 'Durex', null, true, 0.00, true)  /* first timer */,
  (13, 'Queen Myrtle', null, true, 3.00, true),
  (13, 'Wriggle', null, true, 0.00, true)  /* first timer */;

-- Run 14: venue 'Dore & Totley Station' but NO DATE in the sheet (likely the month after run 13).
--   Add its real date + uncomment, OR create it in the admin UI (use this if it
--   is still upcoming, so members can RSVP). Attendees seen in the sheet:
--     Smutley  (fee=None first=False kennel=None role=Hare)
--     Queen Myrtle  (fee=None first=False kennel=None role=Hare)
--     Flying Bottom  (fee=3.0 first=False kennel=None role=None)
--     Wheelchair  (fee=3.0 first=False kennel=None role=None)
--     Tweeny  (fee=3.0 first=False kennel=None role=None)

-- keep the id sequence ahead of the highest run
select setval(pg_get_serial_sequence('public.events','id'), (select max(id) from public.events));

commit;

-- ============ THINGS TO CHECK / CHASE UP ============
-- * Run 4 'Nate': unmapped cell(s) ['Fl']
-- * Run 5 'Horny Devil': BLANK fee in sheet -> loaded as 0 paid. VERIFY.
-- * Run 9: no data in sheet - not created.
-- * Run 10: no data in sheet - not created.
-- * Run 13 'Horse’s Arse': marked OWES -> unpaid 3.00 (debt).
-- * Run 14 (Dore & Totley Station): NO DATE - left out. Create via admin UI or add the date.
