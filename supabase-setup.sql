-- Kontaa: storage for secure receipt links.
-- Paste all of this into Supabase > SQL Editor > New query, then press Run. Safe to run twice.
-- Receipts arrive already scrambled (AES-GCM) by the shop's phone; the key never reaches this database.

create table if not exists public.receipt_links (
  id         text primary key check (char_length(id) between 8 and 32),
  data       text not null check (char_length(data) < 600000),
  created_at timestamptz not null default now()
);

-- No one may read or list the table directly. Row level security with no policies denies everything;
-- the two functions below are the only way in, and each touches exactly one receipt by its id.
alter table public.receipt_links enable row level security;
revoke all on public.receipt_links from anon, authenticated;

create or replace function public.put_receipt(p_id text, p_data text)
returns void language sql security definer set search_path = public as $$
  insert into public.receipt_links (id, data) values (p_id, p_data);
$$;

create or replace function public.get_receipt(p_id text)
returns text language sql stable security definer set search_path = public as $$
  select data from public.receipt_links where id = p_id;
$$;

revoke all on function public.put_receipt(text, text) from public;
revoke all on function public.get_receipt(text) from public;
grant execute on function public.put_receipt(text, text) to anon, authenticated;
grant execute on function public.get_receipt(text) to anon, authenticated;
