
create schema if not exists marwan_private;
revoke all on schema marwan_private from public, anon, authenticated;

create table if not exists public.preferences (
 user_id uuid primary key references auth.users(id) on delete cascade default auth.uid(),
 display_name text not null default '' check(length(display_name)<=100),
 theme text not null default 'auto' check(theme in ('auto','light','dark')),
 timezone text not null default 'Asia/Riyadh',
 ai_mode text not null default 'confirm' check(ai_mode in ('confirm','balanced','wide')),
 ai_model text check(ai_model in ('claude-haiku-5-5','gemini-3.5-flash-lite','gemini-3.8-flash')),
 ai_read_apps text[] not null default '{}',
 home_layout jsonb not null default '{"apps":[],"folders":[],"widgets":[]}',
 updated_at timestamptz not null default now(),
 version integer not null default 1
);
create table if not exists public.items (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 kind text not null check(kind in ('task','event','note','subject','lesson','exam','assignment','study','flashcard','quiz','project','milestone','goal','step','habit','wellness','transaction','budget','worship','idea','folder','review')),
 title text not null check(length(title) between 1 and 300),
 body text not null default '' check(length(body)<=500000),
 status text not null default 'active' check(status in ('active','done','archived','paused')),
 category text not null default '' check(length(category)<=100),
 color text not null default '#75806a' check(color ~ '^#[0-9a-fA-F]{6}$'),
 priority integer not null default 2 check(priority between 1 and 3),
 starts_at timestamptz,
 ends_at timestamptz,
 due_at timestamptz,
 recurrence text not null default 'none' check(recurrence in ('none','daily','weekly','monthly')),
 recurrence_until timestamptz,
 amount numeric(14,2),
 currency text not null default 'SAR' check(currency ~ '^[A-Z]{3}$'),
 data jsonb not null default '{}' check(jsonb_typeof(data)='object' and octet_length(data::text)<=2000000),
 parent_id uuid,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 version integer not null default 1,
 unique(user_id,id),
 foreign key(user_id,parent_id) references public.items(user_id,id) on delete cascade,
 check(parent_id is null or parent_id<>id),
 check(ends_at is null or starts_at is null or ends_at>=starts_at)
);
create index if not exists items_owner_kind on public.items(user_id,kind);
create index if not exists items_parent on public.items(user_id,parent_id);
create index if not exists items_due on public.items(user_id,due_at);
create index if not exists items_starts on public.items(user_id,starts_at);
create index if not exists items_search on public.items using gin(to_tsvector('simple',title||' '||body));

create table if not exists public.links (
 user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 source_id uuid not null,
 target_id uuid not null,
 relation text not null default 'related' check(relation in ('related','subject','project','goal','note','event','exam','task')),
 primary key(user_id,source_id,target_id,relation),
 foreign key(user_id,source_id) references public.items(user_id,id) on delete cascade,
 foreign key(user_id,target_id) references public.items(user_id,id) on delete cascade,
 check(source_id<>target_id)
);
create index if not exists links_target on public.links(user_id,target_id);

create table if not exists public.checkins (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 item_id uuid not null,
 day date not null default ((now() at time zone 'Asia/Riyadh')::date),
 value numeric not null default 1,
 note text not null default '' check(length(note)<=2000),
 created_at timestamptz not null default now(),
 unique(user_id,item_id,day),
 foreign key(user_id,item_id) references public.items(user_id,id) on delete cascade
);
create table if not exists public.attachments (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 item_id uuid not null,
 path text not null unique,
 name text not null check(length(name) between 1 and 255),
 mime_type text not null check(mime_type in ('image/png','image/jpeg','image/webp','application/pdf','text/plain')),
 size_bytes bigint not null check(size_bytes between 1 and 10485760),
 extracted_text text not null default '' check(length(extracted_text)<=500000),
 created_at timestamptz not null default now(),
 foreign key(user_id,item_id) references public.items(user_id,id) on delete cascade,
 check(split_part(path,'/',1)=user_id::text)
);
create index if not exists attachments_item on public.attachments(user_id,item_id);

create table if not exists public.conversations (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 title text not null default 'محادثة جديدة' check(length(title)<=300),
 created_at timestamptz not null default now(),
 unique(user_id,id)
);
create table if not exists public.messages (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 conversation_id uuid not null,
 role text not null check(role in ('user','assistant')),
 content text not null check(length(content)<=100000),
 model text,
 usage jsonb,
 created_at timestamptz not null default now(),
 foreign key(user_id,conversation_id) references public.conversations(user_id,id) on delete cascade
);
create index if not exists messages_conversation on public.messages(user_id,conversation_id,created_at);
create index if not exists conversations_owner on public.conversations(user_id);

create table if not exists public.ai_actions (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 conversation_id uuid,
 operation text not null check(operation in ('create','update')),
 target_id uuid,
 payload jsonb not null,
 before_data jsonb,
 after_version integer,
 status text not null default 'pending' check(status in ('pending','applied','rejected','undone','failed')),
 created_at timestamptz not null default now(),
 resolved_at timestamptz,
 foreign key(user_id,conversation_id) references public.conversations(user_id,id) on delete cascade,
 unique(user_id,id)
);
create index if not exists ai_actions_owner on public.ai_actions(user_id,created_at desc);
create index if not exists ai_actions_conversation on public.ai_actions(user_id,conversation_id);

create table if not exists public.automation_rules (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 name text not null check(length(name) between 1 and 200),
 enabled boolean not null default false,
 trigger_kind text not null check(trigger_kind in ('task','project','goal','exam','assignment')),
 trigger_status text not null default 'done' check(trigger_status in ('active','done','archived','paused')),
 action_kind text not null check(action_kind in ('task','note')),
 action_title text not null check(length(action_title) between 1 and 300),
 created_at timestamptz not null default now(),
 unique(user_id,id)
);
create index if not exists automation_owner on public.automation_rules(user_id);
create table if not exists public.automation_runs (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 rule_id uuid not null,
 source_id uuid not null,
 source_version integer not null,
 result_id uuid not null,
 created_at timestamptz not null default now(),
 unique(rule_id,source_id,source_version),
 foreign key(user_id,rule_id) references public.automation_rules(user_id,id) on delete cascade
);
create index if not exists automation_runs_owner on public.automation_runs(user_id,rule_id);
create table if not exists marwan_private.ai_usage (
 user_id uuid not null references auth.users(id) on delete cascade,
 day date not null default current_date,
 requests integer not null default 0,
 primary key(user_id,day)
);
alter table marwan_private.ai_usage enable row level security;

create or replace function marwan_private.touch_version() returns trigger
 language plpgsql security invoker set search_path='' as $$
begin new.updated_at=now(); new.version=old.version+1; return new; end $$;
drop trigger if exists items_version on public.items;
create trigger items_version before update on public.items for each row execute function marwan_private.touch_version();
drop trigger if exists preferences_version on public.preferences;
create trigger preferences_version before update on public.preferences for each row execute function marwan_private.touch_version();

do $$
declare t text;
begin
 foreach t in array array['preferences','items','links','checkins','attachments','conversations','messages','automation_rules']
 loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from anon, authenticated',t);
 execute format('grant select,insert,update,delete on public.%I to authenticated',t);
 execute format('drop policy if exists own_rows on public.%I',t);
 execute format('create policy own_rows on public.%I for all to authenticated using ((select auth.uid())=user_id) with check ((select auth.uid())=user_id)',t);
 end loop;
 foreach t in array array['ai_actions','automation_runs']
 loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from anon, authenticated',t);
 execute format('grant select on public.%I to authenticated',t);
 execute format('drop policy if exists own_rows on public.%I',t);
 execute format('create policy own_rows on public.%I for select to authenticated using ((select auth.uid())=user_id)',t);
 end loop;
end $$;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
 values('marwan-files','marwan-files',false,10485760,array['image/png','image/jpeg','image/webp','application/pdf','text/plain'])
 on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
drop policy if exists marwan_files_read on storage.objects;
create policy marwan_files_read on storage.objects for select to authenticated
 using(bucket_id='marwan-files' and (storage.foldername(name))[1]=(select auth.uid())::text);
drop policy if exists marwan_files_insert on storage.objects;
create policy marwan_files_insert on storage.objects for insert to authenticated
 with check(bucket_id='marwan-files' and (storage.foldername(name))[1]=(select auth.uid())::text);
drop policy if exists marwan_files_update on storage.objects;
create policy marwan_files_update on storage.objects for update to authenticated
 using(bucket_id='marwan-files' and (storage.foldername(name))[1]=(select auth.uid())::text)
 with check(bucket_id='marwan-files' and (storage.foldername(name))[1]=(select auth.uid())::text);
drop policy if exists marwan_files_delete on storage.objects;
create policy marwan_files_delete on storage.objects for delete to authenticated
 using(bucket_id='marwan-files' and (storage.foldername(name))[1]=(select auth.uid())::text);

create or replace function marwan_private.run_automation() returns trigger
language plpgsql security definer set search_path='' as $$
declare r record; result uuid;
begin
 if pg_trigger_depth()>1 or new.status=old.status then return new; end if;
 for r in select * from public.automation_rules where user_id=new.user_id and enabled and trigger_kind=new.kind and trigger_status=new.status
 loop
  insert into public.items(user_id,kind,title,body,data) values(new.user_id,r.action_kind,r.action_title,'',jsonb_build_object('automation_source',new.id)) returning id into result;
  insert into public.automation_runs(user_id,rule_id,source_id,source_version,result_id) values(new.user_id,r.id,new.id,new.version,result);
 end loop;
 return new;
end $$;
revoke all on function marwan_private.run_automation() from public,anon,authenticated;
drop trigger if exists items_automation on public.items;
create trigger items_automation after update on public.items for each row execute function marwan_private.run_automation();

create or replace function public.search_marwan(q text) returns setof public.items
language sql stable security invoker set search_path='' as $$
 select * from public.items where length(trim(q))>=2 and
 (title ilike '%'||left(q,200)||'%' or body ilike '%'||left(q,200)||'%')
 order by updated_at desc limit 100
$$;
revoke all on function public.search_marwan(text) from public,anon;
grant execute on function public.search_marwan(text) to authenticated;

create or replace function public.reserve_ai_request(p_user uuid) returns boolean
language plpgsql security definer set search_path='' as $$
declare n integer;
begin
 insert into marwan_private.ai_usage(user_id,day,requests) values(p_user,current_date,1)
 on conflict(user_id,day) do update set requests=marwan_private.ai_usage.requests+1
 where marwan_private.ai_usage.requests<30 returning requests into n;
 return n is not null;
end $$;
revoke all on function public.reserve_ai_request(uuid) from public,anon,authenticated;
grant execute on function public.reserve_ai_request(uuid) to service_role;

