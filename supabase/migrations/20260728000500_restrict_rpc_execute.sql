-- Supabase projects can grant function EXECUTE directly to anon and
-- authenticated through default privileges. Revoke every application
-- function explicitly, then grant only the intended client surface.

revoke all on function public.set_updated_at()
  from public, anon, authenticated;
revoke all on function public.handle_new_auth_user()
  from public, anon, authenticated;
revoke all on function public.refresh_group_total_from_share()
  from public, anon, authenticated;
revoke all on function public.refresh_group_total_after_expense_delete()
  from public, anon, authenticated;

revoke all on function public.owns_group(uuid)
  from public, anon, authenticated;
revoke all on function public.owns_expense(uuid)
  from public, anon, authenticated;
revoke all on function public.refresh_group_total(uuid)
  from public, anon, authenticated;
revoke all on function public.recalculate_expense(uuid)
  from public, anon, authenticated;
revoke all on function public.resolve_group_friend(uuid, uuid, text)
  from public, anon, authenticated;

revoke all on function public.create_expense_with_shares(
  uuid, text, numeric, numeric, jsonb, timestamptz
) from public, anon, authenticated;
revoke all on function public.update_expense_with_shares(
  uuid, text, numeric, numeric, jsonb
) from public, anon, authenticated;
revoke all on function public.mark_expense_share_paid(uuid)
  from public, anon, authenticated;
revoke all on function public.mark_friend_shares_paid(uuid, text)
  from public, anon, authenticated;
revoke all on function public.delete_expense(uuid)
  from public, anon, authenticated;

grant execute on function public.owns_group(uuid) to authenticated;
grant execute on function public.owns_expense(uuid) to authenticated;
grant execute on function public.create_expense_with_shares(
  uuid, text, numeric, numeric, jsonb, timestamptz
) to authenticated;
grant execute on function public.update_expense_with_shares(
  uuid, text, numeric, numeric, jsonb
) to authenticated;
grant execute on function public.mark_expense_share_paid(uuid)
  to authenticated;
grant execute on function public.mark_friend_shares_paid(uuid, text)
  to authenticated;
grant execute on function public.delete_expense(uuid)
  to authenticated;
