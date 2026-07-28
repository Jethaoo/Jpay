begin;

create table public.expense_categories (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid references auth.users(id) on delete cascade,
  name text not null,
  normalized_name text generated always as (lower(btrim(name))) stored,
  icon_name text not null default 'category',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint expense_categories_name_not_blank
    check (char_length(btrim(name)) between 1 and 40)
);

create unique index expense_categories_preset_name_unique
  on public.expense_categories (normalized_name)
  where owner_id is null;
create unique index expense_categories_owner_name_unique
  on public.expense_categories (owner_id, normalized_name)
  where owner_id is not null;

insert into public.expense_categories (id, name, icon_name)
values
  ('10000000-0000-4000-8000-000000000001', 'Food & Dining', 'restaurant'),
  ('10000000-0000-4000-8000-000000000002', 'Groceries', 'shopping_basket'),
  ('10000000-0000-4000-8000-000000000003', 'Transport', 'directions_car'),
  ('10000000-0000-4000-8000-000000000004', 'Shopping', 'shopping_bag'),
  ('10000000-0000-4000-8000-000000000005', 'Bills', 'receipt'),
  ('10000000-0000-4000-8000-000000000006', 'Entertainment', 'movie'),
  ('10000000-0000-4000-8000-000000000007', 'Travel', 'flight'),
  ('10000000-0000-4000-8000-000000000008', 'Health', 'health_and_safety'),
  ('10000000-0000-4000-8000-000000000009', 'Other', 'category')
on conflict (id) do nothing;

alter table public.expenses
  add column merchant text not null default '',
  add column notes text not null default '',
  add column category_id uuid references public.expense_categories(id),
  add column category_name text not null default 'Other',
  add column receipt_total numeric(12, 2),
  add column location_label text not null default '',
  add column location_address text not null default '',
  add column latitude double precision,
  add column longitude double precision,
  add column osm_type text,
  add column osm_id text,
  add column attachment_count integer not null default 0,
  add constraint expenses_merchant_length
    check (char_length(btrim(merchant)) <= 120),
  add constraint expenses_notes_length
    check (char_length(notes) <= 2000),
  add constraint expenses_receipt_total_positive
    check (receipt_total is null or receipt_total > 0),
  add constraint expenses_location_pair
    check ((latitude is null) = (longitude is null)),
  add constraint expenses_latitude_range
    check (latitude is null or latitude between -90 and 90),
  add constraint expenses_longitude_range
    check (longitude is null or longitude between -180 and 180),
  add constraint expenses_attachment_count_range
    check (attachment_count between 0 and 5);

update public.expenses
set category_id = '10000000-0000-4000-8000-000000000009'
where category_id is null;

alter table public.expenses
  alter column category_id set default
    '10000000-0000-4000-8000-000000000009',
  alter column category_id set not null;

create table public.expense_attachments (
  id uuid primary key,
  expense_id uuid not null references public.expenses(id) on delete cascade,
  storage_path text not null unique,
  original_filename text not null,
  mime_type text not null,
  size_bytes integer not null,
  sort_order smallint not null,
  ocr_status text not null default 'not_scanned',
  ocr_text text not null default '',
  extracted_data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint expense_attachments_filename_length
    check (char_length(original_filename) between 1 and 255),
  constraint expense_attachments_mime
    check (mime_type in ('image/jpeg', 'image/png', 'image/webp')),
  constraint expense_attachments_size
    check (size_bytes between 1 and 10485760),
  constraint expense_attachments_order
    check (sort_order between 0 and 4),
  constraint expense_attachments_ocr_status
    check (ocr_status in ('not_scanned', 'processing', 'reviewed', 'failed')),
  unique (expense_id, sort_order)
);

create index expense_attachments_expense_idx
  on public.expense_attachments (expense_id, sort_order);
create index expense_attachments_ocr_search_idx
  on public.expense_attachments
  using gin (to_tsvector('simple', ocr_text));
create index expenses_discovery_idx
  on public.expenses (group_id, category_id, expense_date desc);
create index expenses_location_idx
  on public.expenses (group_id, latitude, longitude)
  where latitude is not null;

create trigger expense_categories_set_updated_at
before update on public.expense_categories
for each row execute function public.set_updated_at();

create trigger expense_attachments_set_updated_at
before update on public.expense_attachments
for each row execute function public.set_updated_at();

create or replace function public.refresh_expense_attachment_count()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_expense_id uuid;
  v_count integer;
begin
  if tg_op = 'DELETE' then
    v_expense_id := old.expense_id;
  else
    v_expense_id := new.expense_id;
  end if;
  select count(*)::integer into v_count
  from public.expense_attachments
  where expense_id = v_expense_id;

  if v_count > 5 then
    raise exception 'An expense can have at most five proof images';
  end if;

  update public.expenses
  set attachment_count = v_count
  where id = v_expense_id;
  return null;
end;
$$;

create trigger expense_attachments_refresh_count
after insert or update or delete on public.expense_attachments
for each row execute function public.refresh_expense_attachment_count();

alter table public.expense_categories enable row level security;
alter table public.expense_attachments enable row level security;

create policy expense_categories_select_available
on public.expense_categories for select
to authenticated
using (owner_id is null or owner_id = (select auth.uid()));

create policy expense_categories_insert_own
on public.expense_categories for insert
to authenticated
with check (owner_id = (select auth.uid()));

create policy expense_categories_update_own
on public.expense_categories for update
to authenticated
using (owner_id = (select auth.uid()))
with check (owner_id = (select auth.uid()));

create policy expense_attachments_select_owned
on public.expense_attachments for select
to authenticated
using (public.owns_expense(expense_id));

create or replace function public.validate_expense_category(p_category_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.expense_categories c
    where c.id = p_category_id
      and c.is_active
      and (c.owner_id is null or c.owner_id = (select auth.uid()))
  );
$$;

create or replace function public.insert_expense_attachments(
  p_expense_id uuid,
  p_attachments jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item jsonb;
begin
  if not public.owns_expense(p_expense_id) then
    raise exception 'Expense not found or access denied';
  end if;
  if coalesce(jsonb_typeof(p_attachments), 'array') <> 'array'
      or jsonb_array_length(coalesce(p_attachments, '[]'::jsonb)) > 5 then
    raise exception 'Proof images must be an array of at most five items';
  end if;

  for v_item in
    select value from jsonb_array_elements(coalesce(p_attachments, '[]'::jsonb))
  loop
    if split_part(v_item ->> 'storage_path', '/', 1)
        <> (select auth.uid())::text then
      raise exception 'Invalid proof storage path';
    end if;
    insert into public.expense_attachments (
      id, expense_id, storage_path, original_filename, mime_type, size_bytes,
      sort_order, ocr_status, ocr_text, extracted_data
    ) values (
      (v_item ->> 'id')::uuid,
      p_expense_id,
      v_item ->> 'storage_path',
      v_item ->> 'original_filename',
      v_item ->> 'mime_type',
      (v_item ->> 'size_bytes')::integer,
      (v_item ->> 'sort_order')::smallint,
      coalesce(v_item ->> 'ocr_status', 'not_scanned'),
      coalesce(v_item ->> 'ocr_text', ''),
      coalesce(v_item -> 'extracted_data', '{}'::jsonb)
    );
  end loop;
end;
$$;

create or replace function public.create_expense_record(
  p_group_id uuid,
  p_expense_id uuid,
  p_title text,
  p_merchant text,
  p_notes text,
  p_category_id uuid,
  p_receipt_total numeric,
  p_location jsonb,
  p_tax_percent numeric,
  p_service_percent numeric,
  p_shares jsonb,
  p_attachments jsonb,
  p_expense_date timestamptz default now()
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_expense_id uuid;
  v_item jsonb;
  v_index bigint;
  v_friend_id uuid;
  v_friend_name text;
  v_base numeric(12, 2);
  v_tax numeric(12, 2);
  v_service numeric(12, 2);
begin
  p_tax_percent := coalesce(p_tax_percent, 0);
  p_service_percent := coalesce(p_service_percent, 0);
  p_category_id := coalesce(
    p_category_id,
    '10000000-0000-4000-8000-000000000009'::uuid
  );

  if not public.owns_group(p_group_id) then
    raise exception 'Group not found or access denied';
  end if;
  if char_length(btrim(coalesce(p_title, ''))) = 0 then
    raise exception 'Expense title is required';
  end if;
  if not public.validate_expense_category(p_category_id) then
    raise exception 'Category not found or access denied';
  end if;
  if p_tax_percent < 0 or p_service_percent < 0 then
    raise exception 'Charge percentages cannot be negative';
  end if;
  if jsonb_typeof(p_shares) <> 'array' or jsonb_array_length(p_shares) = 0 then
    raise exception 'At least one expense share is required';
  end if;

  insert into public.expenses (
    id, group_id, title, merchant, notes, category_id, category_name,
    receipt_total,
    location_label, location_address, latitude, longitude, osm_type, osm_id,
    tax_percent, service_percent, expense_date
  ) values (
    coalesce(p_expense_id, gen_random_uuid()),
    p_group_id,
    btrim(p_title),
    btrim(coalesce(p_merchant, '')),
    btrim(coalesce(p_notes, '')),
    p_category_id,
    (select name from public.expense_categories where id = p_category_id),
    p_receipt_total,
    btrim(coalesce(p_location ->> 'label', '')),
    btrim(coalesce(p_location ->> 'address', '')),
    nullif(p_location ->> 'latitude', '')::double precision,
    nullif(p_location ->> 'longitude', '')::double precision,
    nullif(p_location ->> 'osm_type', ''),
    nullif(p_location ->> 'osm_id', ''),
    p_tax_percent,
    p_service_percent,
    coalesce(p_expense_date, now())
  ) returning id into v_expense_id;

  for v_item, v_index in
    select value, ordinality - 1
    from jsonb_array_elements(p_shares) with ordinality
  loop
    v_friend_name := btrim(coalesce(v_item ->> 'friend_name', ''));
    v_base := round((v_item ->> 'base_amount')::numeric, 2);
    if v_base <= 0 then
      raise exception 'Every share amount must be greater than zero';
    end if;
    v_friend_id := public.resolve_group_friend(
      p_group_id,
      nullif(v_item ->> 'friend_id', '')::uuid,
      v_friend_name
    );
    select name into v_friend_name
    from public.group_friends where id = v_friend_id;
    v_tax := round(v_base * p_tax_percent / 100, 2);
    v_service := round(v_base * p_service_percent / 100, 2);

    insert into public.expense_shares (
      expense_id, source_index, friend_id, friend_name, description,
      base_amount, tax_amount, service_amount, amount
    ) values (
      v_expense_id, v_index, v_friend_id, v_friend_name,
      btrim(coalesce(v_item ->> 'description', '')),
      v_base, v_tax, v_service, v_base + v_tax + v_service
    );
  end loop;

  perform public.insert_expense_attachments(v_expense_id, p_attachments);
  perform public.recalculate_expense(v_expense_id);
  perform public.refresh_group_total(p_group_id);
  return v_expense_id;
end;
$$;

create or replace function public.update_expense_record(
  p_expense_id uuid,
  p_title text,
  p_merchant text,
  p_notes text,
  p_category_id uuid,
  p_receipt_total numeric,
  p_location jsonb,
  p_tax_percent numeric,
  p_service_percent numeric,
  p_shares jsonb,
  p_attachments jsonb,
  p_expense_date timestamptz
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.owns_expense(p_expense_id) then
    raise exception 'Expense not found or access denied';
  end if;
  if not public.validate_expense_category(p_category_id) then
    raise exception 'Category not found or access denied';
  end if;

  perform public.update_expense_with_shares(
    p_expense_id, p_title, p_tax_percent, p_service_percent, p_shares
  );

  update public.expenses
  set merchant = btrim(coalesce(p_merchant, '')),
      notes = btrim(coalesce(p_notes, '')),
      category_id = p_category_id,
      category_name = (
        select name from public.expense_categories where id = p_category_id
      ),
      receipt_total = p_receipt_total,
      location_label = btrim(coalesce(p_location ->> 'label', '')),
      location_address = btrim(coalesce(p_location ->> 'address', '')),
      latitude = nullif(p_location ->> 'latitude', '')::double precision,
      longitude = nullif(p_location ->> 'longitude', '')::double precision,
      osm_type = nullif(p_location ->> 'osm_type', ''),
      osm_id = nullif(p_location ->> 'osm_id', ''),
      expense_date = coalesce(p_expense_date, expense_date)
  where id = p_expense_id;

  delete from public.expense_attachments where expense_id = p_expense_id;
  perform public.insert_expense_attachments(p_expense_id, p_attachments);
end;
$$;

create or replace function public.search_group_expenses(
  p_group_id uuid,
  p_query text default '',
  p_category_id uuid default null,
  p_merchant text default '',
  p_location text default '',
  p_from_date timestamptz default null,
  p_to_date timestamptz default null,
  p_has_proof boolean default null,
  p_limit integer default 100,
  p_offset integer default 0
)
returns setof public.expenses
language sql
stable
security definer
set search_path = ''
as $$
  select e.*
  from public.expenses e
  where e.group_id = p_group_id
    and public.owns_group(e.group_id)
    and (p_category_id is null or e.category_id = p_category_id)
    and (p_from_date is null or e.expense_date >= p_from_date)
    and (p_to_date is null or e.expense_date <= p_to_date)
    and (coalesce(btrim(p_merchant), '') = ''
      or e.merchant ilike '%' || btrim(p_merchant) || '%')
    and (coalesce(btrim(p_location), '') = ''
      or concat_ws(' ', e.location_label, e.location_address)
        ilike '%' || btrim(p_location) || '%')
    and (p_has_proof is null
      or (e.attachment_count > 0) = p_has_proof)
    and (
      coalesce(btrim(p_query), '') = ''
      or concat_ws(
        ' ', e.title, e.merchant, e.notes, e.location_label, e.location_address
      ) ilike '%' || btrim(p_query) || '%'
      or exists (
        select 1 from public.expense_shares s
        where s.expense_id = e.id
          and concat_ws(' ', s.friend_name, s.description)
            ilike '%' || btrim(p_query) || '%'
      )
      or exists (
        select 1 from public.expense_attachments a
        where a.expense_id = e.id
          and concat_ws(' ', a.ocr_text, a.extracted_data::text)
            ilike '%' || btrim(p_query) || '%'
      )
    )
  order by e.expense_date desc, e.id
  limit least(greatest(coalesce(p_limit, 100), 1), 500)
  offset greatest(coalesce(p_offset, 0), 0);
$$;

revoke all on public.expense_categories from anon, authenticated;
revoke all on public.expense_attachments from anon, authenticated;
grant select on public.expense_categories to authenticated;
grant insert (owner_id, name, icon_name) on public.expense_categories
  to authenticated;
grant update (name, icon_name, is_active) on public.expense_categories
  to authenticated;
grant select on public.expense_attachments to authenticated;

revoke all on function public.validate_expense_category(uuid) from public;
revoke all on function public.insert_expense_attachments(uuid, jsonb) from public;
revoke all on function public.create_expense_record(
  uuid, uuid, text, text, text, uuid, numeric, jsonb,
  numeric, numeric, jsonb, jsonb, timestamptz
) from public;
revoke all on function public.update_expense_record(
  uuid, text, text, text, uuid, numeric, jsonb,
  numeric, numeric, jsonb, jsonb, timestamptz
) from public;
revoke all on function public.search_group_expenses(
  uuid, text, uuid, text, text, timestamptz, timestamptz,
  boolean, integer, integer
) from public;

grant execute on function public.create_expense_record(
  uuid, uuid, text, text, text, uuid, numeric, jsonb,
  numeric, numeric, jsonb, jsonb, timestamptz
) to authenticated;
grant execute on function public.update_expense_record(
  uuid, text, text, text, uuid, numeric, jsonb,
  numeric, numeric, jsonb, jsonb, timestamptz
) to authenticated;
grant execute on function public.search_group_expenses(
  uuid, text, uuid, text, text, timestamptz, timestamptz,
  boolean, integer, integer
) to authenticated;

insert into storage.buckets (
  id, name, public, file_size_limit, allowed_mime_types
)
values (
  'expense-proofs',
  'expense-proofs',
  false,
  10485760,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create policy expense_proofs_select_own
on storage.objects for select
to authenticated
using (
  bucket_id = 'expense-proofs'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

create policy expense_proofs_insert_own
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'expense-proofs'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

create policy expense_proofs_update_own
on storage.objects for update
to authenticated
using (
  bucket_id = 'expense-proofs'
  and (storage.foldername(name))[1] = (select auth.uid())::text
)
with check (
  bucket_id = 'expense-proofs'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

create policy expense_proofs_delete_own
on storage.objects for delete
to authenticated
using (
  bucket_id = 'expense-proofs'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

alter publication supabase_realtime add table public.expense_categories;
alter publication supabase_realtime add table public.expense_attachments;

commit;
