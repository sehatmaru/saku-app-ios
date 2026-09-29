-- Card colour picked when adding a wallet (hex without #); falls back to the brand colour.
alter table public.accounts add column if not exists color text;
-- Credit card network: visa, mastercard, jcb, amex or gpn. The icon holds the issuing bank.
alter table public.accounts add column if not exists card_network text
  check (card_network in ('visa', 'mastercard', 'jcb', 'amex', 'gpn'));
