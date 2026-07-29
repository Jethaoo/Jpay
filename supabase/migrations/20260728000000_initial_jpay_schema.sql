-- Jpay relational schema.
-- Firebase remains the active backend until the Flutter repository cutover.

create extension if not exists pgcrypto;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  firebase_uid text unique,
  display_name text not null default '',
  photo_path text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_display_name_length
    check (char_length(display_name) <= 80)
);

create table public.groups (
  id uuid primary key default gen_random_uuid(),
  firebase_id text unique,
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  total_owed numeric(12, 2) not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint groups_name_not_blank check (char_length(btrim(name)) > 0),
  constraint groups_name_length check (char_length(btrim(name)) <= 60),
  constraint groups_total_owed_nonnegative check (total_owed >= 0)
);

create unique index groups_owner_normalized_name_key
  on public.groups (owner_id, lower(btrim(name)));
create index groups_owner_created_at_idx
  on public.groups (owner_id, created_at desc);

create table public.group_friends (
  id uuid primary key default gen_random_uuid(),
  firebase_id text,
  group_id uuid not null references public.groups(id) on delete cascade,
  name text not null,
  normalized_name text generated always as (lower(btrim(name))) stored,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint group_friends_name_not_blank
    check (char_length(btrim(name)) > 0),
  constraint group_friends_name_length
    check (char_length(btrim(name)) <= 80),
  unique (group_id, normalized_name),
  unique (group_id, firebase_id)
);

create index group_friends_group_name_idx
  on public.group_friends (group_id, normalized_name);

create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  firebase_id text,
  group_id uuid not null references public.groups(id) on delete cascade,
  title text not null,
  base_total numeric(12, 2) not null default 0,
  tax_percent numeric(8, 4) not null default 0,
  service_percent numeric(8, 4) not null default 0,
  tax_amount numeric(12, 2) not null default 0,
  service_amount numeric(12, 2) not null default 0,
  total_with_charges numeric(12, 2) not null default 0,
  expense_date timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint expenses_title_not_blank check (char_length(btrim(title)) > 0),
  constraint expenses_title_length check (char_length(btrim(title)) <= 160),
  constraint expenses_amounts_nonnegative check (
    base_total >= 0
    and tax_percent >= 0
    and service_percent >= 0
    and tax_amount >= 0
    and service_amount >= 0
    and total_with_charges >= 0
  ),
  unique (group_id, firebase_id)
);

create index expenses_group_date_idx
  on public.expenses (group_id, expense_date desc);

create table public.expense_shares (
  id uuid primary key default gen_random_uuid(),
  expense_id uuid not null references public.expenses(id) on delete cascade,
  source_index integer not null,
  friend_id uuid references public.group_friends(id) on delete set null,
  friend_name text not null,
  description text not null default '',
  base_amount numeric(12, 2) not null,
  tax_amount numeric(12, 2) not null default 0,
  service_amount numeric(12, 2) not null default 0,
  amount numeric(12, 2) not null,
  paid boolean not null default false,
  paid_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint expense_shares_friend_name_not_blank
    check (char_length(btrim(friend_name)) > 0),
  constraint expense_shares_amounts_valid check (
    base_amount > 0
    and tax_amount >= 0
    and service_amount >= 0
    and amount > 0
  ),
  constraint expense_shares_paid_at_valid check (
    (paid and paid_at is not null) or (not paid and paid_at is null)
  ),
  unique (expense_id, source_index)
);

create index expense_shares_expense_idx
  on public.expense_shares (expense_id, source_index);
create index expense_shares_friend_paid_idx
  on public.expense_shares (friend_id, paid);

create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

create trigger groups_set_updated_at
before update on public.groups
for each row execute function public.set_updated_at();

create trigger group_friends_set_updated_at
before update on public.group_friends
for each row execute function public.set_updated_at();

create trigger expenses_set_updated_at
before update on public.expenses
for each row execute function public.set_updated_at();

create trigger expense_shares_set_updated_at
before update on public.expense_shares
for each row execute function public.set_updated_at();

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, firebase_uid, display_name)
  values (
    new.id,
    nullif(new.raw_user_meta_data ->> 'firebase_uid', ''),
    coalesce(
      nullif(new.raw_user_meta_data ->> 'display_name', ''),
      nullif(new.raw_user_meta_data ->> 'full_name', ''),
      ''
    )
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_auth_user();

create or replace function public.owns_group(p_group_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.groups
    where id = p_group_id
      and owner_id = (select auth.uid())
  );
$$;

create or replace function public.owns_expense(p_expense_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.expenses e
    join public.groups g on g.id = e.group_id
    where e.id = p_expense_id
      and g.owner_id = (select auth.uid())
  );
$$;

alter table public.profiles enable row level security;
alter table public.groups enable row level security;
alter table public.group_friends enable row level security;
alter table public.expenses enable row level security;
alter table public.expense_shares enable row level security;

create policy profiles_select_own
on public.profiles for select
to authenticated
using ((select auth.uid()) = id);

create policy profiles_update_own
on public.profiles for update
to authenticated
using ((select auth.uid()) = id)
with check ((select auth.uid()) = id);

create policy groups_select_own
on public.groups for select
to authenticated
using ((select auth.uid()) = owner_id);

create policy groups_insert_own
on public.groups for insert
to authenticated
with check ((select auth.uid()) = owner_id);

create policy groups_update_own
on public.groups for update
to authenticated
using ((select auth.uid()) = owner_id)
with check ((select auth.uid()) = owner_id);

create policy groups_delete_own
on public.groups for delete
to authenticated
using ((select auth.uid()) = owner_id);

create policy group_friends_select_owned_group
on public.group_friends for select
to authenticated
using (public.owns_group(group_id));

create policy group_friends_insert_owned_group
on public.group_friends for insert
to authenticated
with check (public.owns_group(group_id));

create policy group_friends_update_owned_group
on public.group_friends for update
to authenticated
using (public.owns_group(group_id))
with check (public.owns_group(group_id));

create policy group_friends_delete_owned_group
on public.group_friends for delete
to authenticated
using (public.owns_group(group_id));

create policy expenses_select_owned_group
on public.expenses for select
to authenticated
using (public.owns_group(group_id));

create policy expenses_insert_owned_group
on public.expenses for insert
to authenticated
with check (public.owns_group(group_id));

create policy expenses_update_owned_group
on public.expenses for update
to authenticated
using (public.owns_group(group_id))
with check (public.owns_group(group_id));

create policy expenses_delete_owned_group
on public.expenses for delete
to authenticated
using (public.owns_group(group_id));

create policy expense_shares_select_owned_expense
on public.expense_shares for select
to authenticated
using (public.owns_expense(expense_id));

create policy expense_shares_insert_owned_expense
on public.expense_shares for insert
to authenticated
with check (public.owns_expense(expense_id));

create policy expense_shares_update_owned_expense
on public.expense_shares for update
to authenticated
using (public.owns_expense(expense_id))
with check (public.owns_expense(expense_id));

create policy expense_shares_delete_owned_expense
on public.expense_shares for delete
to authenticated
using (public.owns_expense(expense_id));

create or replace function public.refresh_group_total(p_group_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.groups
  set total_owed = coalesce((
    select sum(s.amount)
    from public.expense_shares s
    join public.expenses e on e.id = s.expense_id
    where e.group_id = p_group_id
      and not s.paid
  ), 0)
  where id = p_group_id;
$$;

create or replace function public.refresh_group_total_from_share()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_group_id uuid;
begin
  if tg_op = 'DELETE' then
    select group_id
    into v_group_id
    from public.expenses
    where id = old.expense_id;
  else
    select group_id
    into v_group_id
    from public.expenses
    where id = new.expense_id;
  end if;

  if v_group_id is not null then
    perform public.refresh_group_total(v_group_id);
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create trigger expense_shares_refresh_group_total
after insert or update or delete on public.expense_shares
for each row execute function public.refresh_group_total_from_share();

create or replace function public.refresh_group_total_after_expense_delete()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.refresh_group_total(old.group_id);
  return old;
end;
$$;

create trigger expenses_refresh_group_total_after_delete
after delete on public.expenses
for each row execute function public.refresh_group_total_after_expense_delete();

create or replace function public.recalculate_expense(p_expense_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.expenses
  set
    base_total = totals.base_total,
    tax_amount = totals.tax_amount,
    service_amount = totals.service_amount,
    total_with_charges = totals.total_with_charges
  from (
    select
      coalesce(sum(base_amount), 0) as base_total,
      coalesce(sum(tax_amount), 0) as tax_amount,
      coalesce(sum(service_amount), 0) as service_amount,
      coalesce(sum(amount), 0) as total_with_charges
    from public.expense_shares
    where expense_id = p_expense_id
  ) totals
  where id = p_expense_id;
$$;

create or replace function public.resolve_group_friend(
  p_group_id uuid,
  p_friend_id uuid,
  p_friend_name text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_friend_id uuid;
  v_name text := btrim(p_friend_name);
begin
  if p_friend_id is not null then
    select id into v_friend_id
    from public.group_friends
    where id = p_friend_id and group_id = p_group_id;

    if v_friend_id is null then
      raise exception 'Friend does not belong to this group';
    end if;
    return v_friend_id;
  end if;

  if v_name = '' then
    raise exception 'Friend name is required';
  end if;

  insert into public.group_friends (group_id, name)
  values (p_group_id, v_name)
  on conflict (group_id, normalized_name)
  do update set name = excluded.name
  returning id into v_friend_id;

  return v_friend_id;
end;
$$;

create or replace function public.create_expense_with_shares(
  p_group_id uuid,
  p_title text,
  p_tax_percent numeric,
  p_service_percent numeric,
  p_shares jsonb,
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

  if not public.owns_group(p_group_id) then
    raise exception 'Group not found or access denied';
  end if;
  if char_length(btrim(p_title)) = 0 then
    raise exception 'Expense title is required';
  end if;
  if p_tax_percent < 0 or p_service_percent < 0 then
    raise exception 'Charge percentages cannot be negative';
  end if;
  if jsonb_typeof(p_shares) <> 'array' or jsonb_array_length(p_shares) = 0 then
    raise exception 'At least one expense share is required';
  end if;

  insert into public.expenses (
    group_id,
    title,
    tax_percent,
    service_percent,
    expense_date
  )
  values (
    p_group_id,
    btrim(p_title),
    p_tax_percent,
    p_service_percent,
    coalesce(p_expense_date, now())
  )
  returning id into v_expense_id;

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
    from public.group_friends
    where id = v_friend_id;

    v_tax := round(v_base * p_tax_percent / 100, 2);
    v_service := round(v_base * p_service_percent / 100, 2);

    insert into public.expense_shares (
      expense_id,
      source_index,
      friend_id,
      friend_name,
      description,
      base_amount,
      tax_amount,
      service_amount,
      amount
    )
    values (
      v_expense_id,
      v_index,
      v_friend_id,
      v_friend_name,
      btrim(coalesce(v_item ->> 'description', '')),
      v_base,
      v_tax,
      v_service,
      v_base + v_tax + v_service
    );
  end loop;

  perform public.recalculate_expense(v_expense_id);
  perform public.refresh_group_total(p_group_id);
  return v_expense_id;
end;
$$;

create or replace function public.update_expense_with_shares(
  p_expense_id uuid,
  p_title text,
  p_tax_percent numeric,
  p_service_percent numeric,
  p_shares jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_group_id uuid;
  v_existing jsonb;
  v_item jsonb;
  v_index bigint;
  v_share_id uuid;
  v_friend_id uuid;
  v_friend_name text;
  v_base numeric(12, 2);
  v_tax numeric(12, 2);
  v_service numeric(12, 2);
  v_paid boolean;
  v_paid_at timestamptz;
begin
  p_tax_percent := coalesce(p_tax_percent, 0);
  p_service_percent := coalesce(p_service_percent, 0);

  select group_id into v_group_id
  from public.expenses
  where id = p_expense_id;

  if v_group_id is null or not public.owns_group(v_group_id) then
    raise exception 'Expense not found or access denied';
  end if;
  if char_length(btrim(p_title)) = 0 then
    raise exception 'Expense title is required';
  end if;
  if p_tax_percent < 0 or p_service_percent < 0 then
    raise exception 'Charge percentages cannot be negative';
  end if;
  if jsonb_typeof(p_shares) <> 'array' or jsonb_array_length(p_shares) = 0 then
    raise exception 'At least one expense share is required';
  end if;

  select coalesce(
    jsonb_object_agg(
      id::text,
      jsonb_build_object('paid', paid, 'paid_at', paid_at)
    ),
    '{}'::jsonb
  )
  into v_existing
  from public.expense_shares
  where expense_id = p_expense_id;

  update public.expenses
  set
    title = btrim(p_title),
    tax_percent = p_tax_percent,
    service_percent = p_service_percent
  where id = p_expense_id;

  delete from public.expense_shares where expense_id = p_expense_id;

  for v_item, v_index in
    select value, ordinality - 1
    from jsonb_array_elements(p_shares) with ordinality
  loop
    v_share_id := nullif(v_item ->> 'share_id', '')::uuid;
    v_friend_name := btrim(coalesce(v_item ->> 'friend_name', ''));
    v_base := round((v_item ->> 'base_amount')::numeric, 2);
    if v_base <= 0 then
      raise exception 'Every share amount must be greater than zero';
    end if;

    v_friend_id := public.resolve_group_friend(
      v_group_id,
      nullif(v_item ->> 'friend_id', '')::uuid,
      v_friend_name
    );
    select name into v_friend_name
    from public.group_friends
    where id = v_friend_id;

    v_tax := round(v_base * p_tax_percent / 100, 2);
    v_service := round(v_base * p_service_percent / 100, 2);
    v_paid := coalesce((v_existing -> v_share_id::text ->> 'paid')::boolean, false);
    v_paid_at := case
      when v_paid
        then (v_existing -> v_share_id::text ->> 'paid_at')::timestamptz
      else null
    end;

    insert into public.expense_shares (
      id,
      expense_id,
      source_index,
      friend_id,
      friend_name,
      description,
      base_amount,
      tax_amount,
      service_amount,
      amount,
      paid,
      paid_at
    )
    values (
      coalesce(v_share_id, gen_random_uuid()),
      p_expense_id,
      v_index,
      v_friend_id,
      v_friend_name,
      btrim(coalesce(v_item ->> 'description', '')),
      v_base,
      v_tax,
      v_service,
      v_base + v_tax + v_service,
      v_paid,
      v_paid_at
    );
  end loop;

  perform public.recalculate_expense(p_expense_id);
  perform public.refresh_group_total(v_group_id);
end;
$$;

create or replace function public.mark_expense_share_paid(p_share_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_updated integer;
begin
  update public.expense_shares
  set paid = true, paid_at = now()
  where id = p_share_id
    and not paid
    and public.owns_expense(expense_id);
  get diagnostics v_updated = row_count;
  return v_updated > 0;
end;
$$;

create or replace function public.mark_friend_shares_paid(
  p_group_id uuid,
  p_friend_name text
)
returns numeric
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_total numeric(12, 2);
begin
  if not public.owns_group(p_group_id) then
    raise exception 'Group not found or access denied';
  end if;

  with paid_rows as (
    update public.expense_shares s
    set paid = true, paid_at = now()
    from public.expenses e
    where s.expense_id = e.id
      and e.group_id = p_group_id
      and lower(btrim(s.friend_name)) = lower(btrim(p_friend_name))
      and not s.paid
    returning s.amount
  )
  select coalesce(sum(amount), 0) into v_total from paid_rows;

  perform public.refresh_group_total(p_group_id);
  return v_total;
end;
$$;

create or replace function public.delete_expense(p_expense_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_group_id uuid;
  v_deleted integer;
begin
  select group_id into v_group_id
  from public.expenses
  where id = p_expense_id
    and public.owns_group(group_id);

  if v_group_id is null then
    return false;
  end if;

  delete from public.expenses where id = p_expense_id;
  get diagnostics v_deleted = row_count;
  perform public.refresh_group_total(v_group_id);
  return v_deleted > 0;
end;
$$;

revoke all on public.profiles from anon, authenticated;
revoke all on public.groups from anon, authenticated;
revoke all on public.group_friends from anon, authenticated;
revoke all on public.expenses from anon, authenticated;
revoke all on public.expense_shares from anon, authenticated;

grant select on public.profiles to authenticated;
grant update (display_name, photo_path) on public.profiles to authenticated;

grant select, delete on public.groups to authenticated;
grant insert (owner_id, name) on public.groups to authenticated;
grant update (name) on public.groups to authenticated;

grant select, delete on public.group_friends to authenticated;
grant insert (group_id, name) on public.group_friends to authenticated;
grant update (name) on public.group_friends to authenticated;
grant select on public.expenses to authenticated;
grant select on public.expense_shares to authenticated;

revoke all on function public.owns_group(uuid) from public;
revoke all on function public.owns_expense(uuid) from public;
revoke all on function public.refresh_group_total(uuid) from public;
revoke all on function public.recalculate_expense(uuid) from public;
revoke all on function public.resolve_group_friend(uuid, uuid, text) from public;
revoke all on function public.create_expense_with_shares(
  uuid, text, numeric, numeric, jsonb, timestamptz
) from public;
revoke all on function public.update_expense_with_shares(
  uuid, text, numeric, numeric, jsonb
) from public;
revoke all on function public.mark_expense_share_paid(uuid) from public;
revoke all on function public.mark_friend_shares_paid(uuid, text) from public;
revoke all on function public.delete_expense(uuid) from public;

grant execute on function public.owns_group(uuid) to authenticated;
grant execute on function public.owns_expense(uuid) to authenticated;
grant execute on function public.create_expense_with_shares(
  uuid, text, numeric, numeric, jsonb, timestamptz
) to authenticated;
grant execute on function public.update_expense_with_shares(
  uuid, text, numeric, numeric, jsonb
) to authenticated;
grant execute on function public.mark_expense_share_paid(uuid) to authenticated;
grant execute on function public.mark_friend_shares_paid(uuid, text) to authenticated;
grant execute on function public.delete_expense(uuid) to authenticated;

insert into storage.buckets (id, name, public)
values ('profile-pictures', 'profile-pictures', false)
on conflict (id) do update set public = false;

create policy profile_pictures_select_own
on storage.objects for select
to authenticated
using (
  bucket_id = 'profile-pictures'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

create policy profile_pictures_insert_own
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'profile-pictures'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

create policy profile_pictures_update_own
on storage.objects for update
to authenticated
using (
  bucket_id = 'profile-pictures'
  and (storage.foldername(name))[1] = (select auth.uid())::text
)
with check (
  bucket_id = 'profile-pictures'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

create policy profile_pictures_delete_own
on storage.objects for delete
to authenticated
using (
  bucket_id = 'profile-pictures'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'groups',
    'group_friends',
    'expenses',
    'expense_shares'
  ]
  loop
    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = v_table
    ) then
      execute format(
        'alter publication supabase_realtime add table public.%I',
        v_table
      );
    end if;
  end loop;
end
$$;
