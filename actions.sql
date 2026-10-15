
create or replace function marwan_private.resolve_ai_action(p_id uuid,p_decision text)
returns uuid language plpgsql security definer set search_path='' as $$
declare a public.ai_actions; target public.items; result uuid; who uuid:=auth.uid();
begin
 if who is null then raise exception 'Authentication required'; end if;
 select * into a from public.ai_actions where id=p_id and user_id=who for update;
 if not found then raise exception 'Action unavailable'; end if;
 if p_decision='reject' then
  if a.status<>'pending' then raise exception 'Action already resolved'; end if;
  update public.ai_actions set status='rejected',resolved_at=now() where id=a.id;
  return null;
 elsif p_decision='undo' then
  if a.status<>'applied' then raise exception 'Cannot undo this action'; end if;
  select * into target from public.items where id=a.target_id and user_id=who for update;
  if not found or target.version<>a.after_version then raise exception 'Item changed since this action'; end if;
  if a.operation='create' then
   if exists(select 1 from public.links where user_id=who and (source_id=target.id or target_id=target.id))
    or exists(select 1 from public.items where user_id=who and parent_id=target.id)
    or exists(select 1 from public.attachments where user_id=who and item_id=target.id)
   then raise exception 'Remove related data before undo'; end if;
   delete from public.items where id=target.id and user_id=who;
  else
   update public.items set title=a.before_data->>'title',body=a.before_data->>'body',
    due_at=(a.before_data->>'due_at')::timestamptz,starts_at=(a.before_data->>'starts_at')::timestamptz,
    ends_at=(a.before_data->>'ends_at')::timestamptz where id=target.id and user_id=who;
  end if;
  update public.ai_actions set status='undone',resolved_at=now() where id=a.id;
  return a.target_id;
 elsif p_decision<>'approve' then raise exception 'Invalid decision';
 end if;
 if a.status<>'pending' then raise exception 'Action already resolved'; end if;
 if a.payload->>'kind' not in ('task','event','note') then raise exception 'Unsupported kind'; end if;
 if a.operation='create' then
  insert into public.items(user_id,kind,title,body,due_at,starts_at,ends_at)
  values(who,a.payload->>'kind',a.payload->>'title',coalesce(a.payload->>'body',''),
   (a.payload->>'due_at')::timestamptz,(a.payload->>'starts_at')::timestamptz,(a.payload->>'ends_at')::timestamptz)
  returning * into target;
 else
  select * into target from public.items where id=a.target_id and user_id=who for update;
  if not found or target.kind<>a.payload->>'kind' then raise exception 'Item unavailable'; end if;
  if target.version<>(a.payload->>'expected_version')::integer then raise exception 'Item changed; request a new proposal'; end if;
  update public.ai_actions set before_data=to_jsonb(target) where id=a.id;
  update public.items set title=a.payload->>'title',body=coalesce(a.payload->>'body',''),
   due_at=(a.payload->>'due_at')::timestamptz,starts_at=(a.payload->>'starts_at')::timestamptz,
   ends_at=(a.payload->>'ends_at')::timestamptz
   where id=target.id and user_id=who returning * into target;
 end if;
 update public.ai_actions set status='applied',target_id=target.id,after_version=target.version,resolved_at=now() where id=a.id;
 return target.id;
end $$;
revoke all on function marwan_private.resolve_ai_action(uuid,text) from public,anon;
grant usage on schema marwan_private to authenticated;
grant execute on function marwan_private.resolve_ai_action(uuid,text) to authenticated;
create or replace function public.resolve_ai_action(p_id uuid,p_decision text)
returns uuid language sql security invoker set search_path='' as $$
 select marwan_private.resolve_ai_action(p_id,p_decision)
$$;
revoke all on function public.resolve_ai_action(uuid,text) from public,anon;
grant execute on function public.resolve_ai_action(uuid,text) to authenticated;

