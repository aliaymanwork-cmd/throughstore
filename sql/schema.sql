-- =============================================
-- ABAYAH STORE — Supabase Schema
-- Run this in Supabase SQL Editor
-- =============================================

-- Enable UUID extension
create extension if not exists "uuid-ossp";

-- =============================================
-- PROFILES (extends Supabase auth.users)
-- =============================================
create table public.profiles (
  id uuid references auth.users on delete cascade primary key,
  full_name text,
  phone text,
  avatar_url text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table public.profiles enable row level security;

create policy "Users can view their own profile"
  on public.profiles for select
  using (auth.uid() = id);

create policy "Users can update their own profile"
  on public.profiles for update
  using (auth.uid() = id);

-- Auto-create profile on signup
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, new.raw_user_meta_data->>'full_name');
  return new;
end;
$$ language plpgsql security definer;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();


-- =============================================
-- CATEGORIES
-- =============================================
create table public.categories (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  slug text unique not null,
  description text,
  image_url text,
  display_order int default 0,
  is_active boolean default true,
  created_at timestamptz default now()
);

alter table public.categories enable row level security;

create policy "Anyone can view active categories"
  on public.categories for select
  using (is_active = true);

create policy "Admins can manage categories"
  on public.categories for all
  using (auth.jwt() ->> 'role' = 'admin');

-- Seed categories
insert into public.categories (name, slug, description, display_order) values
  ('Classic Abayas', 'classic-abayas', 'Timeless everyday abayas in premium fabrics', 1),
  ('Luxury Line', 'luxury-line', 'Exclusive embroidered and embellished abayas', 2),
  ('Modest Wear', 'modest-wear', 'Kaftans, jalabiyas and modest coordinates', 3),
  ('Accessories', 'accessories', 'Hijabs, pins and matching accessories', 4);


-- =============================================
-- PRODUCTS
-- =============================================
create table public.products (
  id uuid primary key default uuid_generate_v4(),
  category_id uuid references public.categories(id) on delete set null,
  name text not null,
  slug text unique not null,
  description text,
  price numeric(10,2) not null,
  compare_price numeric(10,2),
  sku text unique,
  stock_quantity int default 0,
  is_active boolean default true,
  is_featured boolean default false,
  tags text[],
  images jsonb default '[]',       -- [{url, alt, position}]
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table public.products enable row level security;

create policy "Anyone can view active products"
  on public.products for select
  using (is_active = true);

create policy "Admins can manage products"
  on public.products for all
  using (auth.jwt() ->> 'role' = 'admin');


-- =============================================
-- PRODUCT VARIANTS (colors/sizes)
-- =============================================
create table public.product_variants (
  id uuid primary key default uuid_generate_v4(),
  product_id uuid references public.products(id) on delete cascade,
  color text,
  color_hex text,
  size text,
  stock_quantity int default 0,
  price_modifier numeric(10,2) default 0,
  sku_suffix text,
  created_at timestamptz default now()
);

alter table public.product_variants enable row level security;

create policy "Anyone can view product variants"
  on public.product_variants for select using (true);

create policy "Admins can manage variants"
  on public.product_variants for all
  using (auth.jwt() ->> 'role' = 'admin');


-- =============================================
-- ADDRESSES
-- =============================================
create table public.addresses (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid references auth.users(id) on delete cascade,
  label text default 'Home',
  full_name text not null,
  phone text not null,
  line1 text not null,
  line2 text,
  city text not null,
  state text not null,
  pincode text not null,
  country text default 'India',
  is_default boolean default false,
  created_at timestamptz default now()
);

alter table public.addresses enable row level security;

create policy "Users can manage their own addresses"
  on public.addresses for all
  using (auth.uid() = user_id);


-- =============================================
-- ORDERS
-- =============================================
create type order_status as enum (
  'pending', 'confirmed', 'processing',
  'shipped', 'delivered', 'cancelled', 'refunded'
);

create type payment_status as enum (
  'pending', 'paid', 'failed', 'refunded'
);

create table public.orders (
  id uuid primary key default uuid_generate_v4(),
  order_number text unique not null default 'ABY-' || upper(substring(uuid_generate_v4()::text, 1, 8)),
  user_id uuid references auth.users(id) on delete set null,
  address_id uuid references public.addresses(id) on delete set null,
  status order_status default 'pending',
  payment_status payment_status default 'pending',
  payment_method text,
  payment_reference text,
  subtotal numeric(10,2) not null,
  discount_amount numeric(10,2) default 0,
  shipping_amount numeric(10,2) default 0,
  tax_amount numeric(10,2) default 0,
  total numeric(10,2) not null,
  coupon_code text,
  notes text,
  shipped_at timestamptz,
  delivered_at timestamptz,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table public.orders enable row level security;

create policy "Users can view their own orders"
  on public.orders for select
  using (auth.uid() = user_id);

create policy "Users can create orders"
  on public.orders for insert
  with check (auth.uid() = user_id);

create policy "Admins can manage all orders"
  on public.orders for all
  using (auth.jwt() ->> 'role' = 'admin');


-- =============================================
-- ORDER ITEMS
-- =============================================
create table public.order_items (
  id uuid primary key default uuid_generate_v4(),
  order_id uuid references public.orders(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null,
  variant_id uuid references public.product_variants(id) on delete set null,
  product_name text not null,
  variant_label text,
  quantity int not null,
  unit_price numeric(10,2) not null,
  total_price numeric(10,2) not null,
  created_at timestamptz default now()
);

alter table public.order_items enable row level security;

create policy "Users can view their own order items"
  on public.order_items for select
  using (
    exists (
      select 1 from public.orders
      where orders.id = order_items.order_id
      and orders.user_id = auth.uid()
    )
  );

create policy "Admins can manage order items"
  on public.order_items for all
  using (auth.jwt() ->> 'role' = 'admin');


-- =============================================
-- WISHLIST
-- =============================================
create table public.wishlists (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid references auth.users(id) on delete cascade,
  product_id uuid references public.products(id) on delete cascade,
  created_at timestamptz default now(),
  unique(user_id, product_id)
);

alter table public.wishlists enable row level security;

create policy "Users can manage their own wishlist"
  on public.wishlists for all
  using (auth.uid() = user_id);


-- =============================================
-- COUPONS
-- =============================================
create type discount_type as enum ('percentage', 'fixed');

create table public.coupons (
  id uuid primary key default uuid_generate_v4(),
  code text unique not null,
  description text,
  discount_type discount_type not null,
  discount_value numeric(10,2) not null,
  min_order_amount numeric(10,2) default 0,
  max_uses int,
  used_count int default 0,
  valid_from timestamptz default now(),
  valid_until timestamptz,
  is_active boolean default true,
  created_at timestamptz default now()
);

alter table public.coupons enable row level security;

create policy "Anyone can view active coupons by code"
  on public.coupons for select
  using (is_active = true);

create policy "Admins can manage coupons"
  on public.coupons for all
  using (auth.jwt() ->> 'role' = 'admin');


-- =============================================
-- REVIEWS
-- =============================================
create table public.reviews (
  id uuid primary key default uuid_generate_v4(),
  product_id uuid references public.products(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  order_id uuid references public.orders(id) on delete set null,
  rating int check (rating between 1 and 5),
  title text,
  body text,
  is_verified boolean default false,
  is_published boolean default false,
  created_at timestamptz default now()
);

alter table public.reviews enable row level security;

create policy "Anyone can view published reviews"
  on public.reviews for select
  using (is_published = true);

create policy "Users can create reviews"
  on public.reviews for insert
  with check (auth.uid() = user_id);

create policy "Admins can manage reviews"
  on public.reviews for all
  using (auth.jwt() ->> 'role' = 'admin');


-- =============================================
-- USEFUL VIEWS
-- =============================================

-- Product with category name & review stats
create view public.products_with_stats as
select
  p.*,
  c.name as category_name,
  c.slug as category_slug,
  coalesce(avg(r.rating), 0) as avg_rating,
  count(r.id) as review_count,
  case when p.compare_price > 0
    then round(((p.compare_price - p.price) / p.compare_price) * 100)
    else 0
  end as discount_percent
from public.products p
left join public.categories c on c.id = p.category_id
left join public.reviews r on r.product_id = p.id and r.is_published = true
group by p.id, c.id;

-- Order summary for admin dashboard
create view public.order_summary as
select
  date_trunc('day', created_at) as day,
  count(*) as total_orders,
  sum(total) as revenue,
  count(*) filter (where status = 'delivered') as delivered,
  count(*) filter (where status = 'cancelled') as cancelled
from public.orders
group by date_trunc('day', created_at)
order by day desc;


-- =============================================
-- INDEXES for performance
-- =============================================
create index on public.products(category_id);
create index on public.products(is_active, is_featured);
create index on public.products(slug);
create index on public.orders(user_id);
create index on public.orders(status);
create index on public.orders(created_at desc);
create index on public.order_items(order_id);
create index on public.wishlists(user_id);
create index on public.reviews(product_id);
