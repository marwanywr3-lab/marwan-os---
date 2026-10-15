
begin;
insert into auth.users(id,aud,role) values('10000000-0000-4000-8000-000000000001','authenticated','authenticated'),('10000000-0000-4000-8000-000000000002','authenticated','authenticated');
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
insert into public.preferences(user_id) values(auth.uid());
insert into public.items(id,kind,title) values('20000000-0000-4000-8000-000000000001','task','RLS acceptance A');
update public.items set title='Updated A' where id='20000000-0000-4000-8000-000000000001';
do $$ begin
 if (select version from public.items where id='20000000-0000-4000-8000-000000000001')<>2 then raise exception 'Version test failed'; end if;
end $$;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',true);
do $$ declare n integer; begin
 if exists(select 1 from public.items where id='20000000-0000-4000-8000-000000000001') then raise exception 'RLS read leak'; end if;
 update public.items set title='hacked' where id='20000000-0000-4000-8000-000000000001';
 get diagnostics n=row_count; if n<>0 then raise exception 'RLS update leak'; end if;
 delete from public.items where id='20000000-0000-4000-8000-000000000001';
 get diagnostics n=row_count; if n<>0 then raise exception 'RLS delete leak'; end if;
 begin
 insert into public.items(user_id,kind,title) values('10000000-0000-4000-8000-000000000001','task','attack');
 raise exception 'RLS insert leak';
 exception when insufficient_privilege then null;
 end;
end $$;
insert into public.items(id,kind,title) values('20000000-0000-4000-8000-000000000002','note','B note');
do $$ begin
 begin
 insert into public.links(source_id,target_id) values('20000000-0000-4000-8000-000000000002','20000000-0000-4000-8000-000000000001');
 raise exception 'Cross account relation allowed';
 exception when foreign_key_violation then null;
 end;
end $$;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
insert into public.automation_rules(name,enabled,trigger_kind,trigger_status,action_kind,action_title) values('test',true,'task','done','note','automated note');
update public.items set status='done' where id='20000000-0000-4000-8000-000000000001';
do $$ begin
 if (select count(*) from public.automation_runs)<>1 then raise exception 'Automation failed'; end if;
end $$;
reset role;
insert into public.ai_actions(id,user_id,operation,payload) values('30000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','create','{"kind":"task","title":"AI approval test"}');
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',true);
do $$ begin
 begin
 perform public.resolve_ai_action('30000000-0000-4000-8000-000000000001','approve');
 raise exception 'AI action ownership leak';
 exception when raise_exception then if sqlerrm<>'Action unavailable' then raise; end if;
 end;
end $$;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
select public.resolve_ai_action('30000000-0000-4000-8000-000000000001','approve');
select public.resolve_ai_action('30000000-0000-4000-8000-000000000001','undo');
do $$ begin
 if exists(select 1 from public.items where title='AI approval test') then raise exception 'Undo failed'; end if;
end $$;
select 'PASS: RLS select/insert/update/delete, composite ownership FK, versioning, event automation, AI action ownership/approval/undo. Transaction rolled back.' as result;
rollback;

