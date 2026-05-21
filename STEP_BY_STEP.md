# Step-by-step — deploy & use (debt tracking + legacy attendees)

Follow these in order. Parts 1 is the one-off deploy; the rest is how to use the
new bits. Hard-refresh (Ctrl-F5) after the deploy.

---

## Part 1 · Deploy (once, in order)

1. **Supabase → SQL Editor → run `0018_debt_tracking.sql`** (if you haven't yet).
2. **Run `0019_legacy_attendees_merge.sql`.**
3. **Re-deploy the `rapid-processor` Edge Function** from
   `supabase/functions/rsvp-email/index.ts`.
   - This carries: the debt-snapshot-on-account-deletion, **and** the email fixes
     (names the right charity + the WhatsApp link) that the live function has been
     missing.
   - ⚠️ After deploying, open the function in the Supabase dashboard and check the
     code actually matches the repo — your last couple of redeploys didn't seem to
     take, which is why the email was still saying "St Luke's".

> No deploy needed beyond this — the rest is just clicking around the admin pages.

---

## Part 2 · Backfill a past event with legacy attendees

The people who came before the website existed.

1. **Admin → Manage events** → open a **past** event (▸ Edit).
2. Click the **attendance tab** ("Ready to On-On" / "After the event" — the one
   with the roster).
3. Under **"Add to the roster"** find **"Add a past attendee (legacy)"**
   (it only shows on past events).
4. Type their **Hash name** (+ **Kennel** if you know it) → **Add**. Repeat for
   everyone who was there.
   - They appear on the roster tagged **"Past member (legacy)"**, £0, already
     marked paid — so they never show as owing money.
5. Repeat for each past event.

That's it — they immediately count in the **Hall of Fame → Top Hounds** on the
admin dashboard.

---

## Part 3 · The legacy-names list

1. **Admin → Legacy attendees** (also linked from the dashboard quick actions).
2. Each row = one hash name you've backfilled: their kennel, how many past events
   they attended, and whether a **matching account** exists yet.
   - "No account yet" = they haven't signed up.
   - "✓ [name]" = a real member with that hash name has signed up.

---

## Part 4 · Merge when someone signs up

This is the bit that stops "Smutley (legacy)" and "Smutley" being two people.

1. When a legacy person **registers**, make sure their **hash name** is set to
   match the legacy one (you set hash names on **Manage members → Edit**).
2. Go to **Legacy attendees** — their row now shows **✓ [name]** and a
   **▸ Merge into account** button.
3. Click **Merge → confirm**. All their backfilled attendances re-attach to the
   real account.
4. Done — the metrics now count them as **one** person, and they drop off the
   legacy list.

---

## Part 5 · Check debt tracking works (from the previous round)

A quick end-to-end:

1. Create or open an event, go to the attendance tab, add 2 people to the roster.
2. Tick **Paid** on one; leave the other **un-ticked**.
3. Watch the **Outstanding** total (top of the tab) — it turns red and shows what's owed.
4. **▸ Save & complete**.
5. **Manage events** → that event now shows a **"Money outstanding £X"** tag.
6. **Manage members** → the un-paid member shows an **"owes £X"** badge (and the
   **Owes money** filter finds them).
7. Open that member → **Outstanding payments** → **▸ Mark paid** → it clears, and
   the event's takings go up.

---

## If something looks off
Note the page + what you did + what you expected. The newest, most likely rough
edges are the **legacy merge** (Part 4) and the **debt totals** (Part 5).
