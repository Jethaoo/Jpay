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

-- 4. Attachment counters must match proof rows and stay within the limit.
select
  e.id,
  e.attachment_count,
  count(a.id)::integer as calculated_attachment_count
from public.expenses e
left join public.expense_attachments a on a.expense_id = e.id
group by e.id, e.attachment_count
having
  e.attachment_count <> count(a.id)::integer
  or count(a.id) > 5;

-- 5. Proof paths must belong to the expense owner's private folder.
select a.id, a.storage_path
from public.expense_attachments a
join public.expenses e on e.id = a.expense_id
join public.groups g on g.id = e.group_id
where split_part(a.storage_path, '/', 1) <> g.owner_id::text;

-- 6. Categories and coordinate pairs must remain valid.
select e.id, e.category_id, e.latitude, e.longitude
from public.expenses e
left join public.expense_categories c on c.id = e.category_id
where c.id is null
   or ((e.latitude is null) <> (e.longitude is null));

-- All six queries should return zero rows.
