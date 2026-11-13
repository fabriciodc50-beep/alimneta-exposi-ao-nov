-- UNIVERSO CRIATIVO | Versão 3 - Backend isolado, acesso público e gestão separados
-- Aplicar uma única vez no Supabase SQL Editor. Nunca coloque service_role no site.
-- Não altera tabelas de outros sistemas: todas usam prefixo uc_.

create extension if not exists pgcrypto;
create table if not exists public.uc_events (
 event_key text primary key,
 title text not null,
 subtitle text not null,
 event_date date not null,
 event_time time not null,
 location text not null,
 allow_registration boolean not null default true,
 created_at timestamptz not null default now()
);
create table if not exists public.uc_items (
 id uuid primary key,
 event_key text not null references public.uc_events(event_key),
 name text not null,
 emoji text not null default '📦',
 group_name text not null,
 category text not null check(category in ('comida','bebida','logistica')),
 target_quantity integer not null default 0 check(target_quantity between 0 and 10000),
 unit text not null default 'un.',
 position integer not null default 0,
 active boolean not null default true
);
create index if not exists uc_items_event_idx on public.uc_items(event_key,position);
create table if not exists public.uc_admins (
 user_id uuid primary key references auth.users(id) on delete cascade,
 created_at timestamptz not null default now()
);
create table if not exists public.uc_attendees (
 id uuid primary key default gen_random_uuid(),
 event_key text not null references public.uc_events(event_key),
 user_id uuid not null references auth.users(id),
 name text not null check(char_length(trim(name)) between 2 and 85),
 share_with text not null default '' check(char_length(share_with)<=80),
 notes text not null default '' check(char_length(notes)<=250),
 icecream_ready boolean not null default true,
 checked_in_at timestamptz,
 status text not null default 'ativo' check(status in ('ativo','cancelado')),
 created_at timestamptz not null default now()
);
create index if not exists uc_attendees_user_idx on public.uc_attendees(user_id,event_key);
create index if not exists uc_attendees_event_idx on public.uc_attendees(event_key);
create table if not exists public.uc_pledges (
 id uuid primary key default gen_random_uuid(),
 attendee_id uuid not null references public.uc_attendees(id) on delete cascade,
 item_id uuid not null references public.uc_items(id),
 quantity integer not null default 1 check(quantity between 1 and 10000),
 delivered_quantity integer not null default 0 check(delivered_quantity>=0 and delivered_quantity<=quantity),
 unique (attendee_id,item_id)
);
create index if not exists uc_pledges_attendee_idx on public.uc_pledges(attendee_id);

alter table public.uc_events enable row level security;
alter table public.uc_items enable row level security;
alter table public.uc_admins enable row level security;
alter table public.uc_attendees enable row level security;
alter table public.uc_pledges enable row level security;

-- Autorização independente de metadados que qualquer usuário poderia alterar.
create or replace function public.uc_is_admin() returns boolean
language sql stable security definer set search_path = ''
as $$select exists(select 1 from public.uc_admins a where a.user_id=(select auth.uid()))$$;
revoke all on function public.uc_is_admin() from public,anon,authenticated;
grant execute on function public.uc_is_admin() to authenticated;

-- Regras de acesso, inclusive para quem inspecionar diretamente a API.
revoke all on public.uc_events,public.uc_items,public.uc_admins,public.uc_attendees,public.uc_pledges from anon,authenticated;
grant select on public.uc_events,public.uc_items to anon,authenticated;
grant update,insert,delete on public.uc_events,public.uc_items to authenticated;
grant select,insert,delete on public.uc_attendees to authenticated;
grant update(name,share_with,notes,icecream_ready) on public.uc_attendees to authenticated;
grant select,insert,delete on public.uc_pledges to authenticated;
grant update(item_id,quantity) on public.uc_pledges to authenticated;
-- Colunas de presença e entregas não têm GRANT de update para participantes.
-- Só as funções de conferência, autorizadas no servidor, alteram esses campos.

drop policy if exists uc_events_public_read on public.uc_events;
create policy uc_events_public_read on public.uc_events for select to anon,authenticated using(true);
drop policy if exists uc_events_admin_insert on public.uc_events;
create policy uc_events_admin_insert on public.uc_events for insert to authenticated with check((select public.uc_is_admin()));
drop policy if exists uc_events_admin_update on public.uc_events;
create policy uc_events_admin_update on public.uc_events for update to authenticated using((select public.uc_is_admin())) with check((select public.uc_is_admin()));
drop policy if exists uc_events_admin_delete on public.uc_events;
create policy uc_events_admin_delete on public.uc_events for delete to authenticated using((select public.uc_is_admin()));

drop policy if exists uc_items_public_read on public.uc_items;
create policy uc_items_public_read on public.uc_items for select to anon,authenticated using(true);
drop policy if exists uc_items_admin_insert on public.uc_items;
create policy uc_items_admin_insert on public.uc_items for insert to authenticated with check((select public.uc_is_admin()));
drop policy if exists uc_items_admin_update on public.uc_items;
create policy uc_items_admin_update on public.uc_items for update to authenticated using((select public.uc_is_admin())) with check((select public.uc_is_admin()));
drop policy if exists uc_items_admin_delete on public.uc_items;
create policy uc_items_admin_delete on public.uc_items for delete to authenticated using((select public.uc_is_admin()));

drop policy if exists uc_attendees_owner_read on public.uc_attendees;
create policy uc_attendees_owner_read on public.uc_attendees for select to authenticated using(user_id=(select auth.uid()) or (select public.uc_is_admin()));
drop policy if exists uc_attendees_owner_insert on public.uc_attendees;
create policy uc_attendees_owner_insert on public.uc_attendees for insert to authenticated with check(user_id=(select auth.uid()) and checked_in_at is null and status='ativo');
drop policy if exists uc_attendees_owner_update on public.uc_attendees;
create policy uc_attendees_owner_update on public.uc_attendees for update to authenticated using((user_id=(select auth.uid()) and checked_in_at is null) or (select public.uc_is_admin())) with check(user_id=(select auth.uid()) or (select public.uc_is_admin()));
drop policy if exists uc_attendees_owner_delete on public.uc_attendees;
create policy uc_attendees_owner_delete on public.uc_attendees for delete to authenticated using((user_id=(select auth.uid()) and checked_in_at is null) or (select public.uc_is_admin()));

drop policy if exists uc_pledges_owner_read on public.uc_pledges;
create policy uc_pledges_owner_read on public.uc_pledges for select to authenticated using(
 exists(select 1 from public.uc_attendees a where a.id=attendee_id and a.user_id=(select auth.uid())) or (select public.uc_is_admin())
);
drop policy if exists uc_pledges_owner_insert on public.uc_pledges;
create policy uc_pledges_owner_insert on public.uc_pledges for insert to authenticated with check(
 delivered_quantity=0 and exists(select 1 from public.uc_attendees a where a.id=attendee_id and a.user_id=(select auth.uid()) and a.checked_in_at is null)
);
drop policy if exists uc_pledges_owner_update on public.uc_pledges;
create policy uc_pledges_owner_update on public.uc_pledges for update to authenticated using(
 exists(select 1 from public.uc_attendees a where a.id=attendee_id and a.user_id=(select auth.uid()) and a.checked_in_at is null)
) with check (
 exists(select 1 from public.uc_attendees a where a.id=attendee_id and a.user_id=(select auth.uid()) and a.checked_in_at is null)
);
drop policy if exists uc_pledges_owner_delete on public.uc_pledges;
create policy uc_pledges_owner_delete on public.uc_pledges for delete to authenticated using(
 exists(select 1 from public.uc_attendees a where a.id=attendee_id and a.user_id=(select auth.uid()) and a.checked_in_at is null)
);

-- Apenas números agregados. Nomes, IDs de participantes e conferência não são expostos ao público.
create or replace function public.uc_public_coverage(p_event_key text)
returns table(item_id uuid,reserved_quantity bigint,delivered_quantity bigint)
language sql stable security definer set search_path = ''
as $$
 select p.item_id,sum(p.quantity)::bigint, sum(p.delivered_quantity)::bigint
 from public.uc_pledges p
 join public.uc_attendees a on a.id=p.attendee_id
 where a.event_key=p_event_key and a.status='ativo'
 group by p.item_id
$$;
revoke all on function public.uc_public_coverage(text) from public,anon,authenticated;
grant execute on function public.uc_public_coverage(text) to anon,authenticated;

-- Conferência real: exige autorização do organizador; nunca baseada em botão HTML.
create or replace function public.uc_admin_arrival(p_attendee_id uuid,p_arrived boolean)
returns boolean language plpgsql security definer set search_path = ''
as $$
begin
 if not public.uc_is_admin() then raise exception 'Acesso restrito ao organizador' using errcode='42501'; end if;
 update public.uc_attendees set checked_in_at=case when p_arrived then now() else null end where id=p_attendee_id;
 if not found then raise exception 'Participante não encontrado'; end if;
 if not p_arrived then update public.uc_pledges set delivered_quantity=0 where attendee_id=p_attendee_id; end if;
 return true;
end;$$;
revoke all on function public.uc_admin_arrival(uuid,boolean) from public,anon,authenticated;
grant execute on function public.uc_admin_arrival(uuid,boolean) to authenticated;

create or replace function public.uc_admin_delivery(p_pledge_id uuid,p_quantity integer)
returns boolean language plpgsql security definer set search_path = ''
as $$
declare max_qty integer;
begin
 if not public.uc_is_admin() then raise exception 'Acesso restrito ao organizador' using errcode='42501'; end if;
 select p.quantity into max_qty from public.uc_pledges p join public.uc_attendees a on a.id=p.attendee_id
 where p.id=p_pledge_id and a.checked_in_at is not null;
 if max_qty is null then raise exception 'Confirme primeiro a chegada do participante'; end if;
 if p_quantity<0 or p_quantity>max_qty then raise exception 'Quantidade inválida'; end if;
 update public.uc_pledges set delivered_quantity=p_quantity where id=p_pledge_id;
 return true;
end;$$;
revoke all on function public.uc_admin_delivery(uuid,integer) from public,anon,authenticated;
grant execute on function public.uc_admin_delivery(uuid,integer) to authenticated;

insert into public.uc_events(event_key,title,subtitle,event_date,event_time,location,allow_registration)
values('universo-criativo-2026','Lanche Coletivo da Exposição','Universo Criativo','2026-11-15','15:00','Praça São Sebastião',true)
on conflict(event_key) do nothing;

-- Catálogo econômico: 100 alimentos, 3 bebidas, 32 itens de apoio.

insert into public.uc_items (id,event_key,name,emoji,group_name,category,target_quantity,unit,position,active) values
('7191408c-cd99-5188-a7e3-e5883f766b0b','universo-criativo-2026','Salgadinho de milho sabor queijo','🥨','Salgadinhos e pipocas','comida',0,'un.',1,true),
('b9e09219-1646-56aa-a1ca-f8561aedeb63','universo-criativo-2026','Salgadinho de milho sabor churrasco','🥨','Salgadinhos e pipocas','comida',0,'un.',2,true),
('9b0449d8-1928-5b35-b68c-552ff0a789a1','universo-criativo-2026','Salgadinho de milho sabor cebola','🥨','Salgadinhos e pipocas','comida',0,'un.',3,true),
('f3905e23-c48d-541a-a306-b0ac3c907dd9','universo-criativo-2026','Batata chips tradicional','🥨','Salgadinhos e pipocas','comida',0,'un.',4,true),
('eecf56a5-9516-519b-a1c9-a2c749c57e2d','universo-criativo-2026','Batata chips ondulada','🥨','Salgadinhos e pipocas','comida',0,'un.',5,true),
('db939822-b158-5acf-8e9f-cbc0be70199b','universo-criativo-2026','Salgadinho tipo torcida','🥨','Salgadinhos e pipocas','comida',0,'un.',6,true),
('4117b04c-cc5d-5516-8a38-a628f3d4917e','universo-criativo-2026','Salgadinho tipo bacon','🥨','Salgadinhos e pipocas','comida',0,'un.',7,true),
('9ca0bd81-4355-5f33-ba8e-6b0d632f3add','universo-criativo-2026','Salgadinho de trigo','🥨','Salgadinhos e pipocas','comida',0,'un.',8,true),
('64b833d5-92d4-55a7-ab28-0d86e029378e','universo-criativo-2026','Salgadinho de queijo de pacote','🥨','Salgadinhos e pipocas','comida',0,'un.',9,true),
('211ec21e-7b5c-5562-965c-375325ef20b4','universo-criativo-2026','Salgadinho de presunto','🥨','Salgadinhos e pipocas','comida',0,'un.',10,true),
('4a6e64f8-29b9-5095-a53b-1d71c43d02a6','universo-criativo-2026','Salgadinho tipo nachos','🥨','Salgadinhos e pipocas','comida',0,'un.',11,true),
('0dfd7bd6-badb-5bf0-9b0c-49e791c1350d','universo-criativo-2026','Pipoca salgada de pacote','🥨','Salgadinhos e pipocas','comida',0,'un.',12,true),
('b2d005e6-6bd7-5a80-8572-83d08333ee90','universo-criativo-2026','Pipoca salgada pronta (pacote pequeno)','🥨','Salgadinhos e pipocas','comida',0,'un.',13,true),
('57528f59-c519-56dc-907a-c83159e9e146','universo-criativo-2026','Milho torrado salgado','🥨','Salgadinhos e pipocas','comida',0,'un.',14,true),
('b7707f94-2d75-56b0-a2f6-2f1693d26801','universo-criativo-2026','Amendoim torrado salgado','🥨','Salgadinhos e pipocas','comida',0,'un.',15,true),
('9efc3cea-3ee9-5be5-81f2-959e22b4625c','universo-criativo-2026','Amendoim japonês','🥨','Salgadinhos e pipocas','comida',0,'un.',16,true),
('da17c2bb-dc42-56dc-ad62-c5b3149ac502','universo-criativo-2026','Amendoim doce de pacote','🥨','Salgadinhos e pipocas','comida',0,'un.',17,true),
('aefd34bc-aab9-5cc0-8028-0fab8380ef9b','universo-criativo-2026','Salgadinho de mandioca','🥨','Salgadinhos e pipocas','comida',0,'un.',18,true),
('e2b2191d-2cc7-5bfa-ad4a-5779179c11f8','universo-criativo-2026','Salgadinho de arroz','🥨','Salgadinhos e pipocas','comida',0,'un.',19,true),
('752626a0-8289-597b-827c-7c2eb87fdcbc','universo-criativo-2026','Mini pretzels de pacote','🥨','Salgadinhos e pipocas','comida',0,'un.',20,true),
('9f49574a-6f11-5f9a-9634-fd879a06b816','universo-criativo-2026','Bolacha recheada de chocolate','🍪','Bolachas doces','comida',0,'un.',21,true),
('7559a4ec-f8a0-5adc-9882-4d05aaa38a3f','universo-criativo-2026','Bolacha recheada de morango','🍪','Bolachas doces','comida',0,'un.',22,true),
('48f07fe7-423b-594f-a1cd-cb6c14d0d4ac','universo-criativo-2026','Bolacha recheada de baunilha','🍪','Bolachas doces','comida',0,'un.',23,true),
('20711e40-eb7f-5932-8f6e-5104f21e025d','universo-criativo-2026','Bolacha recheada de limão','🍪','Bolachas doces','comida',0,'un.',24,true),
('b76e1216-14b4-53f0-8a78-9f321e9d55bd','universo-criativo-2026','Bolacha recheada de doce de leite','🍪','Bolachas doces','comida',0,'un.',25,true),
('161a9fcd-2e6f-5d60-b9b3-b9d175744e15','universo-criativo-2026','Bolacha tipo maisena','🍪','Bolachas doces','comida',0,'un.',26,true),
('59c46a34-7abb-5a4f-808a-467348c507c8','universo-criativo-2026','Bolacha tipo Maria','🍪','Bolachas doces','comida',0,'un.',27,true),
('36e62938-7636-55ba-a882-0da81cc5d97d','universo-criativo-2026','Bolacha de leite','🍪','Bolachas doces','comida',0,'un.',28,true),
('2fe0bdb0-4dd3-573d-a134-3bb41ee6fed5','universo-criativo-2026','Bolacha amanteigada','🍪','Bolachas doces','comida',0,'un.',29,true),
('776c8ba8-dad3-51bf-8455-7368bf90919d','universo-criativo-2026','Bolacha de coco','🍪','Bolachas doces','comida',0,'un.',30,true),
('aace0102-9f25-57cd-8735-627217cf7a60','universo-criativo-2026','Bolacha de chocolate','🍪','Bolachas doces','comida',0,'un.',31,true),
('d66c6f3e-f4cd-551d-97f5-502e5485c8b9','universo-criativo-2026','Bolacha wafer chocolate','🍪','Bolachas doces','comida',0,'un.',32,true),
('e5e3abec-86c8-5617-b9e7-ae7528c9517e','universo-criativo-2026','Bolacha wafer morango','🍪','Bolachas doces','comida',0,'un.',33,true),
('fae3d0ea-84d1-5ba9-ac48-c31c1407c256','universo-criativo-2026','Bolacha wafer baunilha','🍪','Bolachas doces','comida',0,'un.',34,true),
('3c45f1fe-6b55-510d-8161-6d9e83530c4e','universo-criativo-2026','Rosquinha de coco','🍪','Bolachas doces','comida',0,'un.',35,true),
('2165b373-ff09-5b10-a652-0da16c6b7f4b','universo-criativo-2026','Rosquinha de chocolate','🍪','Bolachas doces','comida',0,'un.',36,true),
('fdf5f1cb-966e-576c-a7ac-fe04710a8567','universo-criativo-2026','Rosquinha de leite','🍪','Bolachas doces','comida',0,'un.',37,true),
('30dd7a8a-47ed-5e44-8051-541efab67511','universo-criativo-2026','Biscoito de polvilho doce','🍪','Bolachas doces','comida',0,'un.',38,true),
('a75a6095-29f4-5e68-b418-e8b19ffb3dcb','universo-criativo-2026','Bolachinha tipo sequilho','🍪','Bolachas doces','comida',0,'un.',39,true),
('0549f92e-41cc-57f5-83f0-2c9c112178eb','universo-criativo-2026','Bolacha doce sortida','🍪','Bolachas doces','comida',0,'un.',40,true),
('0bf9f10e-dfe5-5a43-9015-103535e0ad3b','universo-criativo-2026','Biscoito água e sal','🧂','Biscoitos salgados','comida',0,'un.',41,true),
('8792c583-0af9-5987-b884-2f9f87c16add','universo-criativo-2026','Biscoito cream cracker','🧂','Biscoitos salgados','comida',0,'un.',42,true),
('0f1d1b08-dc16-59b7-958b-f665db402e96','universo-criativo-2026','Biscoito salgado integral','🧂','Biscoitos salgados','comida',0,'un.',43,true),
('9aaf99d5-556b-58d1-a2d8-dde52cf8832b','universo-criativo-2026','Biscoito salgado sabor queijo','🧂','Biscoitos salgados','comida',0,'un.',44,true),
('a7056395-3d44-5866-aa6f-f7127a671039','universo-criativo-2026','Biscoito salgado sabor cebola','🧂','Biscoitos salgados','comida',0,'un.',45,true),
('df5bee4c-4e48-5c88-aa07-97d72e185050','universo-criativo-2026','Biscoito tipo club social','🧂','Biscoitos salgados','comida',0,'un.',46,true),
('653e8b7e-b077-5034-bc1c-705da1750652','universo-criativo-2026','Biscoito salgado com gergelim','🧂','Biscoitos salgados','comida',0,'un.',47,true),
('ccbe8eb1-1911-536f-9b2c-c656c8ce30b8','universo-criativo-2026','Biscoito de polvilho salgado','🧂','Biscoitos salgados','comida',0,'un.',48,true),
('72880adf-3b17-5f49-974f-1716fc87bb5c','universo-criativo-2026','Palitinho salgado de pacote','🧂','Biscoitos salgados','comida',0,'un.',49,true),
('bb471659-8bb9-5bfc-81bc-6e00d3963116','universo-criativo-2026','Torradinha de pacote','🧂','Biscoitos salgados','comida',0,'un.',50,true),
('e7857c1e-45fb-5e33-aa3b-a4a0a175c6ac','universo-criativo-2026','Mini torradas salgadas','🧂','Biscoitos salgados','comida',0,'un.',51,true),
('6e8bf262-03dc-53fc-840d-5621019bf30e','universo-criativo-2026','Biscoito salgado de leite','🧂','Biscoitos salgados','comida',0,'un.',52,true),
('a14e2b94-a408-5905-a11e-9eb3eb5e56c4','universo-criativo-2026','Rosquinha salgada','🧂','Biscoitos salgados','comida',0,'un.',53,true),
('447021f0-fe14-586a-a3a4-33d74e8fb82c','universo-criativo-2026','Cracker de pacote','🧂','Biscoitos salgados','comida',0,'un.',54,true),
('bf9cac9a-5bcc-533a-a5d8-a3907640431b','universo-criativo-2026','Bolo caseiro de fubá','🍞','Bolos e pães simples','comida',0,'un.',55,true),
('f882468b-5909-5920-a296-10ac323bdb5a','universo-criativo-2026','Bolo simples de cenoura','🍞','Bolos e pães simples','comida',0,'un.',56,true),
('3459cf02-980f-58e8-bfc3-4aec738d76c5','universo-criativo-2026','Bolo caseiro de chocolate','🍞','Bolos e pães simples','comida',0,'un.',57,true),
('48bb74c8-9791-597c-9b3b-cdd5da7696bd','universo-criativo-2026','Bolo de laranja simples','🍞','Bolos e pães simples','comida',0,'un.',58,true),
('f30dc2a2-c986-5cca-af10-beba81dea3b4','universo-criativo-2026','Bolo de milho simples','🍞','Bolos e pães simples','comida',0,'un.',59,true),
('1c893dd4-6e9d-5ed2-82d4-756621c4b762','universo-criativo-2026','Bolo mesclado simples','🍞','Bolos e pães simples','comida',0,'un.',60,true),
('f3943103-ac5a-546b-9f6d-7c539eb2759f','universo-criativo-2026','Bolo de baunilha simples','🍞','Bolos e pães simples','comida',0,'un.',61,true),
('d7920105-9e90-5f74-82d6-a46e3a78ab07','universo-criativo-2026','Bolo de coco simples','🍞','Bolos e pães simples','comida',0,'un.',62,true),
('11dad551-ba2c-58fa-9784-2273cbd63183','universo-criativo-2026','Bolo simples de limão','🍞','Bolos e pães simples','comida',0,'un.',63,true),
('8f1c5e61-4024-594c-b882-ce62886c4867','universo-criativo-2026','Pão de forma tradicional','🍞','Bolos e pães simples','comida',0,'un.',64,true),
('07d9f819-210e-5ea5-b03e-5469effceb43','universo-criativo-2026','Pão francês simples','🍞','Bolos e pães simples','comida',0,'un.',65,true),
('61c3aea1-3f1b-5134-974a-56b8e28c3211','universo-criativo-2026','Bisnaguinha de pacote','🍞','Bolos e pães simples','comida',0,'un.',66,true),
('64370c52-bd67-5eea-9810-fb2727465f1d','universo-criativo-2026','Pão doce simples','🍞','Bolos e pães simples','comida',0,'un.',67,true),
('81bd82f5-0235-55f7-8a2a-1c83dda06275','universo-criativo-2026','Pão de leite de pacote','🍞','Bolos e pães simples','comida',0,'un.',68,true),
('be6d4188-649b-59d1-bb6f-7881ca748845','universo-criativo-2026','Mini pão francês','🍞','Bolos e pães simples','comida',0,'un.',69,true),
('32d86205-600d-52ac-9d0c-6524b0bde279','universo-criativo-2026','Pão de queijo pronto de mercado','🍞','Bolos e pães simples','comida',0,'un.',70,true),
('3bf6631c-436b-5b1b-ac35-4d6e64fbeb88','universo-criativo-2026','Paçoca de rolha','🍬','Doces baratos de mercado','comida',0,'un.',71,true),
('c2bbe552-f41a-5ef3-a514-85ae1100ce34','universo-criativo-2026','Paçoca quadrada','🍬','Doces baratos de mercado','comida',0,'un.',72,true),
('1c851c5c-cfa2-513a-93d0-e772d1343b70','universo-criativo-2026','Pé de moleque de pacote','🍬','Doces baratos de mercado','comida',0,'un.',73,true),
('14b407de-0e14-5c64-8160-b7d5366ff00e','universo-criativo-2026','Bala de goma de pacote','🍬','Doces baratos de mercado','comida',0,'un.',74,true),
('65338935-e645-5499-bc69-5f9c87c83fb0','universo-criativo-2026','Bala mastigável de pacote','🍬','Doces baratos de mercado','comida',0,'un.',75,true),
('76fdda42-a08c-5811-a8e5-6455aadd7876','universo-criativo-2026','Bala de coco','🍬','Doces baratos de mercado','comida',0,'un.',76,true),
('99f76c37-1de9-5478-9193-106f83beee9c','universo-criativo-2026','Bala de hortelã','🍬','Doces baratos de mercado','comida',0,'un.',77,true),
('e6703853-43a5-541b-8280-7f698578570f','universo-criativo-2026','Pirulito de pacote','🍬','Doces baratos de mercado','comida',0,'un.',78,true),
('26747008-0d7e-5127-96e6-f1a55521dc70','universo-criativo-2026','Marshmallow simples de pacote','🍬','Doces baratos de mercado','comida',0,'un.',79,true),
('d3b7fb46-8fd8-5e1e-ade1-10e239f2e955','universo-criativo-2026','Tablete de chocolate econômico','🍬','Doces baratos de mercado','comida',0,'un.',80,true),
('9e55fc68-bee3-5d43-b602-5abf213ee249','universo-criativo-2026','Bombom de pacote econômico','🍬','Doces baratos de mercado','comida',0,'un.',81,true),
('d3a4cd8a-95ad-53e8-9fab-d55544d571bd','universo-criativo-2026','Doce de amendoim de pacote','🍬','Doces baratos de mercado','comida',0,'un.',82,true),
('3001f805-1f8a-5b3c-98a8-b86ad4141ad9','universo-criativo-2026','Goiabada em cubinhos','🍬','Doces baratos de mercado','comida',0,'un.',83,true),
('dff42075-44c6-57c5-8a25-881e1b01a377','universo-criativo-2026','Rapadura em pedaços','🍬','Doces baratos de mercado','comida',0,'un.',84,true),
('84056db5-de0d-559a-b547-4e8b343ac6f7','universo-criativo-2026','Mini sanduíches de pão de forma','🥪','Lanches econômicos','comida',0,'un.',85,true),
('ead4644a-4186-52b9-b923-372f42de025d','universo-criativo-2026','Sanduíches de pão com margarina','🥪','Lanches econômicos','comida',0,'un.',86,true),
('19511719-8b18-54f0-b422-e7862514b3c7','universo-criativo-2026','Sanduíches com queijo (em bolsa térmica)','🥪','Lanches econômicos','comida',0,'un.',87,true),
('8b7308c2-8eb8-5dc1-b446-9bc1bce99428','universo-criativo-2026','Pão com mortadela (em bolsa térmica)','🥪','Lanches econômicos','comida',0,'un.',88,true),
('87dd69c3-9d2c-58d9-92e9-8ca858449356','universo-criativo-2026','Pão com presunto (em bolsa térmica)','🥪','Lanches econômicos','comida',0,'un.',89,true),
('2c0bea2b-cbad-569c-985b-e82176a21b5e','universo-criativo-2026','Pão com requeijão (em bolsa térmica)','🥪','Lanches econômicos','comida',0,'un.',90,true),
('7ad0863b-9afa-5044-8d3b-234d829bcf95','universo-criativo-2026','Mini cachorro-quente simples','🥪','Lanches econômicos','comida',0,'un.',91,true),
('e1ef32a4-20a8-55b5-beb9-44d0495d23dc','universo-criativo-2026','Pão com patê (em bolsa térmica)','🥪','Lanches econômicos','comida',0,'un.',92,true),
('10c7be7e-b3ac-5028-b952-0e1ac7c9bfcb','universo-criativo-2026','Mini torradas com margarina','🥪','Lanches econômicos','comida',0,'un.',93,true),
('5c7e21c7-1533-5932-b0d8-42445c5eb8b8','universo-criativo-2026','Torradas com geleia em pote','🥪','Lanches econômicos','comida',0,'un.',94,true),
('6b713937-1024-59f9-8461-3e51ee05986e','universo-criativo-2026','Pão de alho assado','🥪','Lanches econômicos','comida',0,'un.',95,true),
('3533a4ad-affa-542e-8589-ad0457d39fe5','universo-criativo-2026','Pãozinho recheado simples','🥪','Lanches econômicos','comida',0,'un.',96,true),
('d5055632-5b71-5898-ba75-fe5177956719','universo-criativo-2026','Bolo pronto de pacote (fatiado)','🥪','Lanches econômicos','comida',0,'un.',97,true),
('143af39d-c384-526d-85f0-c115377c2bf0','universo-criativo-2026','Pão de milho simples','🥪','Lanches econômicos','comida',0,'un.',98,true),
('05cc59df-0629-5a8a-b8b2-a316e30dd46c','universo-criativo-2026','Mini pão doce embalado','🥪','Lanches econômicos','comida',0,'un.',99,true),
('eb0e79b1-210d-50bd-a68a-841a53662e83','universo-criativo-2026','Sanduíche natural simples (em bolsa térmica)','🥪','Lanches econômicos','comida',0,'un.',100,true),
('f69c7ce4-e862-5aeb-9cb7-15b533336100','universo-criativo-2026','Refrigerante de 2 litros','🥤','Bebidas','bebida',0,'garrafas',101,true),
('1e10c29f-bffc-54af-ad7e-ac93f343554d','universo-criativo-2026','Água mineral (para quem não bebe refrigerante)','💧','Bebidas','bebida',0,'garrafas',102,true),
('b5bc235a-bccf-5806-8abe-8567bd1d74a0','universo-criativo-2026','Suco (para quem não bebe refrigerante)','🧃','Bebidas','bebida',0,'un.',103,true),
('b05929ce-f689-5007-8e37-706c53fb7c36','universo-criativo-2026','Mesa dobrável','🪑','Organização e utensílios','logistica',3,'un.',104,true),
('3c731f01-c19f-58a6-89de-37cc8b56ffda','universo-criativo-2026','Mesa auxiliar','🪑','Organização e utensílios','logistica',1,'un.',105,true),
('b20e62d3-00ed-5ae7-9b77-494cb669f58a','universo-criativo-2026','Toalha para mesa','🧺','Organização e utensílios','logistica',4,'un.',106,true),
('c898e537-bfcb-55cf-bdf0-31e3db7667a3','universo-criativo-2026','Cadeiras dobráveis','🪑','Organização e utensílios','logistica',6,'un.',107,true),
('695a3b2f-e106-5ce1-92ce-0e711d02421f','universo-criativo-2026','Cooler / caixa térmica','🧊','Organização e utensílios','logistica',3,'un.',108,true),
('d32e630c-0970-5586-857b-a413d1016027','universo-criativo-2026','Gelo em saco','🧊','Organização e utensílios','logistica',6,'sacos',109,true),
('fe53d92e-6a02-5aa7-b8e9-c943d9c45809','universo-criativo-2026','Copos descartáveis','🥤','Organização e utensílios','logistica',120,'un.',110,true),
('35324c67-eb5e-5a5f-af02-93d1c3a99d60','universo-criativo-2026','Pratos descartáveis','🍽️','Organização e utensílios','logistica',80,'un.',111,true),
('3c0a293c-3377-5fd7-824d-6d756a68141a','universo-criativo-2026','Guardanapos','🧻','Organização e utensílios','logistica',5,'pacotes',112,true),
('2ab24773-b6cc-5ab7-9d75-042c3e23ab80','universo-criativo-2026','Papel-toalha','🧻','Organização e utensílios','logistica',3,'rolos',113,true),
('8555b1b1-4c42-5623-b117-fddb3b115c3c','universo-criativo-2026','Sacos de lixo reforçados','🗑️','Organização e utensílios','logistica',10,'un.',114,true),
('853b8a35-f2d7-5614-962b-a153493c96d6','universo-criativo-2026','Sacolas extras para transporte','🛍️','Organização e utensílios','logistica',8,'un.',115,true),
('6949678c-6c8e-56b5-b29f-e4d8c8395497','universo-criativo-2026','Garfos descartáveis','🍴','Organização e utensílios','logistica',60,'un.',116,true),
('150a3d88-cab4-528e-89f7-b31d20e96cb1','universo-criativo-2026','Colheres descartáveis','🥄','Organização e utensílios','logistica',60,'un.',117,true),
('77c7a42b-aca4-55d2-a1cc-88452cdbddd9','universo-criativo-2026','Facas de servir','🔪','Organização e utensílios','logistica',3,'un.',118,true),
('3e9af842-b37a-50e5-b03a-b2aa0464745d','universo-criativo-2026','Facas descartáveis','🍴','Organização e utensílios','logistica',60,'un.',119,true),
('ca135599-7f82-557c-967d-3e004c358798','universo-criativo-2026','Tábuas de corte','🪵','Organização e utensílios','logistica',2,'un.',120,true),
('57513402-11fe-57c5-a18f-2d3efee0faba','universo-criativo-2026','Abridor de garrafa','🍾','Organização e utensílios','logistica',2,'un.',121,true),
('403a0f71-37b0-5a7b-9e96-dadef0a7a566','universo-criativo-2026','Tesoura','✂️','Organização e utensílios','logistica',2,'un.',122,true),
('4299e67d-ca71-51ed-ad17-ddb0750ffdf0','universo-criativo-2026','Potes com tampa','🥡','Organização e utensílios','logistica',8,'un.',123,true),
('103c9d1b-1353-565d-a774-1cfe9c1a182a','universo-criativo-2026','Bandejas para servir','🍽️','Organização e utensílios','logistica',6,'un.',124,true),
('8dff0493-cbb5-5e2a-9282-2862d5dd2508','universo-criativo-2026','Pegadores de alimentos','🥢','Organização e utensílios','logistica',3,'un.',125,true),
('1e03e213-2f8f-574e-a6b8-19ca549268a9','universo-criativo-2026','Pano para limpeza','🧽','Organização e utensílios','logistica',3,'un.',126,true),
('a9f2ee98-03f6-5a33-b658-a29157875f10','universo-criativo-2026','Álcool em gel','🧴','Organização e utensílios','logistica',3,'frascos',127,true),
('e958e5ea-e8e3-5f28-80dc-a2310ebee592','universo-criativo-2026','Lenços umedecidos','🧻','Organização e utensílios','logistica',2,'pacotes',128,true),
('626ab9a2-8658-5b6b-ac74-ff440202ef81','universo-criativo-2026','Caixas para organização','📦','Organização e utensílios','logistica',4,'un.',129,true),
('2e203be7-11d9-5fbd-86e2-cc1e5e4fde9e','universo-criativo-2026','Prendedores de toalha','📎','Organização e utensílios','logistica',8,'un.',130,true),
('53b17920-0cd6-51fb-80b2-3e2401319c13','universo-criativo-2026','Extensão elétrica (se necessária)','🔌','Organização e utensílios','logistica',1,'un.',131,true),
('15a0ef0a-8aaa-5399-ada4-fd1bed3420a5','universo-criativo-2026','Guarda-sol / cobertura','⛱️','Organização e utensílios','logistica',2,'un.',132,true),
('8d72bee2-0cf7-5a4e-80fd-d10571fe95f3','universo-criativo-2026','Fita adesiva','📦','Organização e utensílios','logistica',2,'rolos',133,true),
('da0190c4-7add-5c7e-a9e9-862239939c95','universo-criativo-2026','Toalha de chão / canga','🧺','Organização e utensílios','logistica',3,'un.',134,true),
('3746f0e7-55a9-5348-ba8f-6ea136405571','universo-criativo-2026','Colher grande para servir','🥄','Organização e utensílios','logistica',3,'un.',135,true)
on conflict(id) do nothing;

-- Depois de criar uma conta com e-mail e senha em Supabase > Authentication > Users,
-- cadastre-a como organizador (substitua o e-mail):
-- INSERT INTO public.uc_admins(user_id) SELECT id FROM auth.users WHERE email='email-do-organizador@exemplo.com' ON CONFLICT DO NOTHING;
-- Não execute esse INSERT com e-mail fictício.
