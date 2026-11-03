-- CENTRAL PENAL / FiveM
-- Execute este arquivo no SQL Editor do seu projeto Supabase.
-- Use somente dados fictícios de personagens do jogo.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'Policial',
  email text,
  role text not null default 'officer' check (role in ('admin','officer')),
  created_at timestamptz not null default now()
);

create table if not exists public.system_settings (
  id integer primary key default 1 check (id = 1),
  fixed_amount numeric(14,2) not null default 200000 check (fixed_amount >= 0),
  updated_at timestamptz not null default now()
);
insert into public.system_settings(id,fixed_amount) values (1,200000) on conflict (id) do nothing;

create table if not exists public.weekly_closures (
  id uuid primary key default gen_random_uuid(),
  period_start date not null,
  period_end date not null,
  arrest_count integer not null default 0,
  total_amount numeric(16,2) not null default 0,
  paid boolean not null default false,
  closed_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  check (period_end >= period_start)
);

create table if not exists public.arrests (
  id uuid primary key default gen_random_uuid(),
  police_id uuid not null references public.profiles(id),
  prisoner_name text not null,
  prisoner_id text not null,
  crimes text not null,
  sentence text,
  description text,
  photo_path text,
  amount numeric(14,2) not null default 200000,
  closure_id uuid references public.weekly_closures(id),
  created_at timestamptz not null default now()
);
create index if not exists arrests_created_at_idx on public.arrests(created_at desc);
create index if not exists arrests_police_id_idx on public.arrests(police_id);
create index if not exists arrests_closure_id_idx on public.arrests(closure_id);

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.profiles where id=auth.uid() and role='admin') $$;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=public
as $$ begin
  insert into public.profiles(id,display_name,email,role)
  values(new.id,coalesce(new.raw_user_meta_data->>'display_name',split_part(new.email,'@',1)),new.email,'officer')
  on conflict(id) do nothing;
  return new;
end; $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();

create or replace function public.set_arrest_amount()
returns trigger language plpgsql security definer set search_path=public
as $$ begin
  select fixed_amount into new.amount from public.system_settings where id=1;
  return new;
end; $$;
drop trigger if exists arrests_set_amount on public.arrests;
create trigger arrests_set_amount before insert on public.arrests for each row execute procedure public.set_arrest_amount();

create or replace function public.close_week(p_start date,p_end date)
returns uuid language plpgsql security definer set search_path=public
as $$
declare v_id uuid; v_count integer; v_total numeric(16,2);
begin
  if not public.is_admin() then raise exception 'Apenas administradores podem fechar períodos.'; end if;
  if p_end < p_start then raise exception 'Período inválido.'; end if;
  if exists(select 1 from public.weekly_closures where period_start=p_start and period_end=p_end) then raise exception 'Este período já foi fechado.'; end if;
  select count(*),coalesce(sum(amount),0) into v_count,v_total from public.arrests
   where closure_id is null and created_at >= p_start::timestamptz and created_at < (p_end+1)::timestamptz;
  if v_count=0 then raise exception 'Não existem prisões pendentes neste período.'; end if;
  insert into public.weekly_closures(period_start,period_end,arrest_count,total_amount,closed_by)
   values(p_start,p_end,v_count,v_total,auth.uid()) returning id into v_id;
  update public.arrests set closure_id=v_id where closure_id is null
   and created_at >= p_start::timestamptz and created_at < (p_end+1)::timestamptz;
  return v_id;
end; $$;

alter table public.profiles enable row level security;
alter table public.system_settings enable row level security;
alter table public.weekly_closures enable row level security;
alter table public.arrests enable row level security;

drop policy if exists "profiles read authenticated" on public.profiles;
create policy "profiles read authenticated" on public.profiles for select to authenticated using (true);
drop policy if exists "profiles update self or admin" on public.profiles;
drop policy if exists "profiles update admin only" on public.profiles;
create policy "profiles update admin only" on public.profiles for update to authenticated using (public.is_admin()) with check (public.is_admin());
-- Somente administradores podem alterar perfis e cargos; usuários não podem promover a si mesmos.

drop policy if exists "settings read authenticated" on public.system_settings;
create policy "settings read authenticated" on public.system_settings for select to authenticated using (true);
drop policy if exists "settings update admin" on public.system_settings;
create policy "settings update admin" on public.system_settings for update to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "closures read authenticated" on public.weekly_closures;
create policy "closures read authenticated" on public.weekly_closures for select to authenticated using (true);
drop policy if exists "closures update admin" on public.weekly_closures;
create policy "closures update admin" on public.weekly_closures for update to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "arrests read authenticated" on public.arrests;
create policy "arrests read authenticated" on public.arrests for select to authenticated using (true);
drop policy if exists "arrests insert self" on public.arrests;
create policy "arrests insert self" on public.arrests for insert to authenticated with check (police_id=auth.uid());
drop policy if exists "arrests update admin" on public.arrests;
create policy "arrests update admin" on public.arrests for update to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "arrests delete admin" on public.arrests;
create policy "arrests delete admin" on public.arrests for delete to authenticated using (public.is_admin());

-- Bucket privado para fotografias. Os arquivos ficam acessíveis apenas a usuários autenticados.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('prisoner-photos','prisoner-photos',false,8388608,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=false,file_size_limit=8388608,allowed_mime_types=array['image/jpeg','image/png','image/webp'];

drop policy if exists "photos read authenticated" on storage.objects;
create policy "photos read authenticated" on storage.objects for select to authenticated using (bucket_id='prisoner-photos');
drop policy if exists "photos upload own folder" on storage.objects;
create policy "photos upload own folder" on storage.objects for insert to authenticated with check (bucket_id='prisoner-photos' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists "photos delete admin or owner" on storage.objects;
create policy "photos delete admin or owner" on storage.objects for delete to authenticated using (bucket_id='prisoner-photos' and ((storage.foldername(name))[1]=auth.uid()::text or public.is_admin()));

-- Depois de criar sua primeira conta, promova-a a administradora no SQL Editor:
-- update public.profiles set role='admin', display_name='Nome do Administrador' where email='SEU_EMAIL_AQUI';
