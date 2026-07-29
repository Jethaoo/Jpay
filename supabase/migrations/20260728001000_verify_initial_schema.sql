-- Deployment assertions for the initial Jpay schema.
-- This migration changes no application data. Each assertion is a separate
-- statement so deployment output identifies the failing security category.

-- Statement 0: all application tables exist with RLS enabled.
do $$
declare
  v_missing text[];
begin
  select array_agg(expected.table_name order by expected.table_name)
  into v_missing
  from (
    values
      ('profiles'),
      ('groups'),
      ('group_friends'),
      ('expenses'),
      ('expense_shares')
  ) as expected(table_name)
  where not exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = expected.table_name
      and c.relkind = 'r'
      and c.relrowsecurity
  );

  if v_missing is not null then
    raise exception 'Missing tables or RLS is disabled: %', v_missing;
  end if;
end
$$;

-- Statement 1: the complete set of public-table policies exists.
do $$
declare
  v_policy_count integer;
begin
  select count(*)
  into v_policy_count
  from pg_policies
  where schemaname = 'public'
    and tablename in (
      'profiles',
      'groups',
      'group_friends',
      'expenses',
      'expense_shares'
    );

  if v_policy_count <> 18 then
    raise exception 'Expected 18 public-table RLS policies, found %',
      v_policy_count;
  end if;
end
$$;

-- Statement 2: tables needed by the Flutter streams are in Realtime.
do $$
declare
  v_missing text[];
begin
  select array_agg(expected.table_name order by expected.table_name)
  into v_missing
  from (
    values
      ('groups'),
      ('group_friends'),
      ('expenses'),
      ('expense_shares')
  ) as expected(table_name)
  where not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = expected.table_name
  );

  if v_missing is not null then
    raise exception 'Tables missing from Supabase Realtime: %', v_missing;
  end if;
end
$$;

-- Statement 3: profile pictures use a private bucket.
do $$
begin
  if not exists (
    select 1
    from storage.buckets
    where id = 'profile-pictures'
      and name = 'profile-pictures'
      and not public
  ) then
    raise exception 'Private profile-pictures bucket is missing';
  end if;
end
$$;

-- Statement 4: profile picture access is protected by four policies.
do $$
declare
  v_policy_count integer;
begin
  select count(*)
  into v_policy_count
  from pg_policies
  where schemaname = 'storage'
    and tablename = 'objects'
    and policyname in (
      'profile_pictures_select_own',
      'profile_pictures_insert_own',
      'profile_pictures_update_own',
      'profile_pictures_delete_own'
    );

  if v_policy_count <> 4 then
    raise exception 'Expected 4 profile picture policies, found %',
      v_policy_count;
  end if;
end
$$;

-- Statement 5: table and column grants protect derived balances.
do $$
begin
  if has_table_privilege('anon', 'public.groups', 'select') then
    raise exception 'Anonymous users must not have groups table privileges';
  end if;

  if not has_table_privilege(
    'authenticated',
    'public.groups',
    'select'
  ) then
    raise exception 'Authenticated users require groups SELECT';
  end if;

  if not has_column_privilege(
    'authenticated',
    'public.groups',
    'name',
    'update'
  ) then
    raise exception 'Authenticated users require groups.name UPDATE';
  end if;

  if has_column_privilege(
    'authenticated',
    'public.groups',
    'total_owed',
    'update'
  ) then
    raise exception 'Clients must not update groups.total_owed directly';
  end if;
end
$$;

-- Statement 6: authenticated users can call all client-facing RPCs.
do $$
declare
  v_missing text[];
begin
  select array_agg(expected.function_name order by expected.function_name)
  into v_missing
  from (
    values
      ('create_expense_with_shares'),
      ('update_expense_with_shares'),
      ('mark_expense_share_paid'),
      ('mark_friend_shares_paid'),
      ('delete_expense')
  ) as expected(function_name)
  where not exists (
    select 1
    from information_schema.routine_privileges rp
    where rp.routine_schema = 'public'
      and rp.routine_name = expected.function_name
      and rp.grantee = 'authenticated'
      and rp.privilege_type = 'EXECUTE'
  );

  if v_missing is not null then
    raise exception 'Authenticated role cannot execute functions: %',
      v_missing;
  end if;
end
$$;

-- Statement 7: anonymous and public roles cannot call mutating RPCs.
do $$
declare
  v_exposed text[];
begin
  select array_agg(expected.function_name order by expected.function_name)
  into v_exposed
  from (
    values
      ('create_expense_with_shares'),
      ('update_expense_with_shares'),
      ('mark_expense_share_paid'),
      ('mark_friend_shares_paid'),
      ('delete_expense')
  ) as expected(function_name)
  where exists (
    select 1
    from information_schema.routine_privileges rp
    where rp.routine_schema = 'public'
      and rp.routine_name = expected.function_name
      and rp.grantee in ('anon', 'PUBLIC')
      and rp.privilege_type = 'EXECUTE'
  );

  if v_exposed is not null then
    raise exception 'Functions are executable by anonymous/public roles: %',
      v_exposed;
  end if;
end
$$;

-- Statement 8: internal security-definer helpers are not client-callable.
do $$
declare
  v_exposed text[];
begin
  select array_agg(expected.function_name order by expected.function_name)
  into v_exposed
  from (
    values
      ('set_updated_at'),
      ('handle_new_auth_user'),
      ('refresh_group_total_from_share'),
      ('refresh_group_total_after_expense_delete'),
      ('refresh_group_total'),
      ('recalculate_expense'),
      ('resolve_group_friend')
  ) as expected(function_name)
  where exists (
    select 1
    from information_schema.routine_privileges rp
    where rp.routine_schema = 'public'
      and rp.routine_name = expected.function_name
      and rp.grantee in ('anon', 'authenticated', 'PUBLIC')
      and rp.privilege_type = 'EXECUTE'
  );

  if v_exposed is not null then
    raise exception 'Internal functions are client-executable: %', v_exposed;
  end if;
end
$$;
