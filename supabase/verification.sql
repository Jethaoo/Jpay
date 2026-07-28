-- Run after applying the migration and importing a test account.
-- Replace the UUID values before executing.

-- 1. Group totals must equal the sum of unpaid shares.
select
  g.id,
  g.name,
  g.total_owed as stored_total,
  coalesce(sum(s.amount) filter (where not s.paid), 0) as calculated_total
from public.groups g
left join public.expenses e on e.group_id = g.id
left join public.expense_shares s on s.expense_id = e.id
group by g.id, g.name, g.total_owed
having g.total_owed <> coalesce(sum(s.amount) filter (where not s.paid), 0);

-- 2. Expense totals must equal their share totals.
select
  e.id,
  e.title,
  e.base_total,
  coalesce(sum(s.base_amount), 0) as calculated_base_total,
  e.total_with_charges,
  coalesce(sum(s.amount), 0) as calculated_total_with_charges
from public.expenses e
left join public.expense_shares s on s.expense_id = e.id
group by e.id, e.title, e.base_total, e.total_with_charges
having
  e.base_total <> coalesce(sum(s.base_amount), 0)
  or e.total_with_charges <> coalesce(sum(s.amount), 0);

-- 3. Every group and imported Firebase record must map to an Auth user.
select g.id, g.firebase_id, g.owner_id
from public.groups g
left join auth.users u on u.id = g.owner_id
where u.id is null;

-- All three queries should return zero rows.
