-- Kontaa: owner accounts (shop sync between phones).
-- Paste all of this into Supabase > SQL Editor > New query, then press Run. Safe to run twice.
-- Every record arrives already locked (AES-GCM) with the shop's key, which never reaches this database.
-- The database only sees a token derived from the key, and stores just a fingerprint (SHA-256) of it.

create table if not exists public.shops (
  id         text primary key check (char_length(id) between 8 and 32),
  token_hash text not null,
  created_at timestamptz not null default now()
);

create sequence if not exists public.shop_rows_seq;

create table if not exists public.shop_rows (
  shop_id    text not null references public.shops(id) on delete cascade,
  k          text not null check (char_length(k) <= 80),
  d          text not null check (char_length(d) < 300000),
  seq        bigint not null default nextval('public.shop_rows_seq'),
  updated_at timestamptz not null default now(),
  primary key (shop_id, k)
);
create index if not exists shop_rows_shop_seq on public.shop_rows (shop_id, seq);

-- Nobody may read or list these tables directly; only the functions below get in, and each one
-- checks the shop's token first.
alter table public.shops enable row level security;
alter table public.shop_rows enable row level security;
revoke all on public.shops, public.shop_rows from anon, authenticated;

create or replace function public.kontaa_check(p_shop text, p_token text)
returns void language plpgsql stable security definer set search_path = public as $$
begin
  if not exists (select 1 from shops where id = p_shop
                 and token_hash = encode(sha256(convert_to(p_token, 'UTF8')), 'hex')) then
    raise exception 'unknown shop or wrong key' using errcode = '28000';
  end if;
end $$;

create or replace function public.create_shop(p_shop text, p_token text)
returns void language sql security definer set search_path = public as $$
  insert into shops (id, token_hash) values (p_shop, encode(sha256(convert_to(p_token, 'UTF8')), 'hex'));
$$;

create or replace function public.sync_put(p_shop text, p_token text, p_rows jsonb)
returns bigint language plpgsql security definer set search_path = public as $$
declare last bigint;
begin
  perform kontaa_check(p_shop, p_token);
  if jsonb_array_length(p_rows) > 300 then raise exception 'too many rows'; end if;
  insert into shop_rows (shop_id, k, d)
    select p_shop, r->>'k', r->>'d' from jsonb_array_elements(p_rows) r
  on conflict (shop_id, k) do update
    set d = excluded.d, seq = nextval('public.shop_rows_seq'), updated_at = now();
  select max(seq) into last from shop_rows where shop_id = p_shop;
  return last;
end $$;

create or replace function public.sync_get(p_shop text, p_token text, p_since bigint)
returns table (k text, d text, seq bigint) language plpgsql stable security definer set search_path = public as $$
begin
  perform kontaa_check(p_shop, p_token);
  return query select r.k, r.d, r.seq from shop_rows r
    where r.shop_id = p_shop and r.seq > p_since order by r.seq limit 500;
end $$;

revoke all on function public.kontaa_check(text, text) from public, anon, authenticated;
revoke all on function public.create_shop(text, text) from public;
revoke all on function public.sync_put(text, text, jsonb) from public;
revoke all on function public.sync_get(text, text, bigint) from public;
grant execute on function public.create_shop(text, text) to anon, authenticated;
grant execute on function public.sync_put(text, text, jsonb) to anon, authenticated;
grant execute on function public.sync_get(text, text, bigint) to anon, authenticated;
