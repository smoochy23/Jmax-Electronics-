-- ONLINE STORE DATABASE (secure version 2)
-- Run this whole file once in Supabase > SQL Editor > New query > Run.
-- Safe to run again: it will not duplicate anything.

-- 1. Who is the owner
create table if not exists public.owners(email text primary key);
alter table public.owners enable row level security;      -- no policies: nobody can read it directly
insert into public.owners(email) values ('jamesmwangi200023@gmail.com') on conflict do nothing;

create or replace function public.is_owner() returns boolean
language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.owners where lower(email)=lower(coalesce(auth.jwt()->>'email','')))
$$;
grant execute on function public.is_owner() to anon, authenticated;

-- 2. Store settings (editable from the Owner dashboard)
create table if not exists public.settings(id int primary key default 1 check (id=1), delivery_fee int not null default 300);
alter table public.settings add column if not exists store_name text default 'My Electronics';
alter table public.settings add column if not exists tagline text default 'Phones, audio and accessories delivered to your door.';
alter table public.settings add column if not exists currency text default 'KSh';
alter table public.settings add column if not exists phone text default '0111909865';
alter table public.settings add column if not exists paybill text default '542542';
alter table public.settings add column if not exists account text default '02308979546150';
insert into public.settings(id) values (1) on conflict do nothing;

-- 3. Products and orders
create table if not exists public.products(
  id bigint primary key,
  name text not null,
  price numeric not null default 0 check (price>=0),
  cat text default '',
  stock integer not null default 0 check (stock>=0),
  "desc" text default '',
  icon text default '📦',
  img text default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.orders(
  id text primary key,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  name text not null, phone text not null, address text not null, note text default '',
  items jsonb not null,
  fee numeric not null default 0,
  total numeric not null,
  payment_method text not null check (payment_method in ('mpesa','delivery')),
  mpesa_code text,
  status text not null default 'pending' check (status in ('pending','paid','delivered','cancelled'))
);
create unique index if not exists orders_mpesa_uidx on public.orders(mpesa_code) where mpesa_code is not null;

-- 4. Security: shoppers read products/settings only; only the owner sees orders or changes anything
alter table public.settings enable row level security;
alter table public.products enable row level security;
alter table public.orders enable row level security;
drop policy if exists "Public can view products" on public.products;
drop policy if exists "Owner can insert products" on public.products;
drop policy if exists "Owner can update products" on public.products;
drop policy if exists "Owner can delete products" on public.products;
drop policy if exists "Anyone can place an order" on public.orders;
drop policy if exists "Owner can read orders" on public.orders;
drop policy if exists "Owner can update orders" on public.orders;
drop policy if exists "public read products" on public.products;
drop policy if exists "public read settings" on public.settings;
drop policy if exists "owner products" on public.products;
drop policy if exists "owner settings" on public.settings;
drop policy if exists "owner orders" on public.orders;
create policy "public read products" on public.products for select to anon, authenticated using (true);
create policy "public read settings" on public.settings for select to anon, authenticated using (true);
create policy "owner products" on public.products for all to authenticated using (public.is_owner()) with check (public.is_owner());
create policy "owner settings" on public.settings for all to authenticated using (public.is_owner()) with check (public.is_owner());
create policy "owner orders" on public.orders for all to authenticated using (public.is_owner()) with check (public.is_owner());

create or replace function public.set_updated_at() returns trigger language plpgsql as $$
begin new.updated_at=now(); return new; end $$;
drop trigger if exists products_set_updated_at on public.products;
create trigger products_set_updated_at before update on public.products for each row execute function public.set_updated_at();
drop trigger if exists orders_set_updated_at on public.orders;
create trigger orders_set_updated_at before update on public.orders for each row execute function public.set_updated_at();

-- 5. Shoppers place orders ONLY through this function (prices, stock and delivery fee are checked here)
create or replace function public.place_order(p_name text,p_phone text,p_address text,p_note text,p_pay text,p_mpesa text,p_items jsonb)
returns json language plpgsql security definer set search_path=public as $$
declare it jsonb; pr public.products%rowtype; q int; v_sub numeric:=0; v_fee numeric; v_lines jsonb:='[]'; v_id text; v_tot numeric; mp text;
begin
  if coalesce(trim(p_name),'')='' or coalesce(trim(p_phone),'')='' or coalesce(trim(p_address),'')='' then
    raise exception 'Name, phone and address are required'; end if;
  if p_pay not in ('mpesa','delivery') then raise exception 'Invalid payment method'; end if;
  mp:=upper(trim(coalesce(p_mpesa,'')));
  if p_pay='mpesa' then
    if mp !~ '^[A-Z0-9]{10}$' then raise exception 'Enter the 10-character M-Pesa confirmation code'; end if;
    if exists(select 1 from public.orders where mpesa_code=mp) then raise exception 'That M-Pesa code was already used on another order'; end if;
  else mp:=null; end if;
  if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'Your cart is empty'; end if;
  for it in select value from jsonb_array_elements(p_items) loop
    q:=(it->>'qty')::int;
    if q<1 or q>50 then raise exception 'Invalid quantity'; end if;
    select * into pr from public.products where id=(it->>'id')::bigint for update;
    if not found then raise exception 'A product in your cart is no longer available'; end if;
    if pr.stock<q then raise exception 'Not enough stock for %', pr.name; end if;
    update public.products set stock=stock-q where id=pr.id;
    v_sub:=v_sub+pr.price*q;
    v_lines:=v_lines||jsonb_build_object('id',pr.id,'name',pr.name,'price',pr.price,'n',q);
  end loop;
  select delivery_fee into v_fee from public.settings where id=1;
  v_fee:=coalesce(v_fee,0); v_tot:=v_sub+v_fee;
  v_id:='ORD-'||upper(substr(md5(random()::text||clock_timestamp()::text),1,6));
  insert into public.orders(id,name,phone,address,note,items,fee,total,payment_method,mpesa_code)
  values(v_id,trim(p_name),trim(p_phone),trim(p_address),coalesce(p_note,''),v_lines,v_fee,v_tot,p_pay,mp);
  return json_build_object('id',v_id,'total',v_tot,'fee',v_fee,'items',v_lines);
end $$;
grant execute on function public.place_order(text,text,text,text,text,text,jsonb) to anon, authenticated;

-- Shopper can check an order's status with order number + phone
create or replace function public.get_order_status(p_id text,p_phone text) returns text
language sql security definer set search_path=public as $$
  select status from public.orders where id=p_id and phone=p_phone limit 1 $$;
grant execute on function public.get_order_status(text,text) to anon, authenticated;

-- Owner cancels an order and the stock goes back
create or replace function public.cancel_order(p_id text) returns void
language plpgsql security definer set search_path=public as $$
declare o public.orders%rowtype; it jsonb;
begin
  if not public.is_owner() then raise exception 'Not allowed'; end if;
  select * into o from public.orders where id=p_id for update;
  if not found or o.status='cancelled' then return; end if;
  for it in select value from jsonb_array_elements(o.items) loop
    update public.products set stock=stock+(it->>'n')::int where id=(it->>'id')::bigint;
  end loop;
  update public.orders set status='cancelled' where id=p_id;
end $$;
grant execute on function public.cancel_order(text) to authenticated;

-- 6. Product photo storage (owner uploads, everyone can view)
insert into storage.buckets(id,name,public) values('products','products',true) on conflict do nothing;
drop policy if exists "public read photos" on storage.objects;
drop policy if exists "owner upload photos" on storage.objects;
drop policy if exists "owner update photos" on storage.objects;
drop policy if exists "owner delete photos" on storage.objects;
create policy "public read photos" on storage.objects for select using (bucket_id='products');
create policy "owner upload photos" on storage.objects for insert to authenticated with check (bucket_id='products' and public.is_owner());
create policy "owner update photos" on storage.objects for update to authenticated using (bucket_id='products' and public.is_owner());
create policy "owner delete photos" on storage.objects for delete to authenticated using (bucket_id='products' and public.is_owner());

-- 7. Sample products (edit or delete them in the Owner dashboard)
insert into public.products(id,name,price,cat,stock,"desc",icon) values
 (1,'Smartphone 128GB',18500,'Phones',5,'Sample item. Edit or delete me.','📱'),
 (2,'Wireless Earbuds',2800,'Audio',12,'Sample item. Bluetooth with charging case.','🎧'),
 (3,'Smart Watch',4500,'Wearables',7,'Sample item. Heart-rate and sleep tracking.','⌚'),
 (4,'20,000mAh Power Bank',2200,'Accessories',0,'Sample item. Fast charging.','🔋')
on conflict (id) do nothing;
