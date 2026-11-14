-- FAGA XPRESS : espace livreur (à exécuter dans LE BON projet Supabase)
create table if not exists public.livreurs (
  id uuid primary key default gen_random_uuid(),
  nom text not null, tel text not null,
  actif boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.livreurs add column if not exists code_acces text not null
  default upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
alter table public.livreurs enable row level security;
drop policy if exists "livreurs admin" on public.livreurs;
create policy "livreurs admin" on public.livreurs for all to authenticated using (true) with check (true);
alter table public.orders add column if not exists livreur_id uuid references public.livreurs(id) on delete set null;
alter table public.orders add column if not exists assigned_at timestamptz;

create or replace function public.livreur_orders(p_tel text, p_code text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare l livreurs; r jsonb;
begin
  select * into l from livreurs where actif
    and right(regexp_replace(tel,'\D','','g'),8) = right(regexp_replace(p_tel,'\D','','g'),8)
    and upper(code_acces) = upper(trim(p_code)) limit 1;
  if not found then return null; end if;
  select coalesce(jsonb_agg(jsonb_build_object('code',o.code,'statut',o.statut,'nom',o.nom,'tel',o.tel,
    'retrait',o.retrait,'livraison',o.livraison,'destinataire',o.destinataire,'tel_destinataire',o.tel_destinataire,
    'contenu',o.contenu,'taille',o.taille,'date_livraison',o.date_livraison,'heure_recuperation',o.heure_recuperation,
    'option',o.option,'instructions',o.instructions,'tarif_final',o.tarif_final) order by o.created_at desc),'[]'::jsonb)
  into r from orders o where o.livreur_id = l.id
    and (o.statut in ('Confirmée','En cours de livraison') or (o.statut = 'Livrée' and o.created_at > now() - interval '3 days'));
  return r;
end $$;

create or replace function public.livreur_set_statut(p_tel text, p_code text, p_order text, p_statut text) returns boolean
language plpgsql security definer set search_path = public as $$
declare l livreurs; n int;
begin
  if p_statut not in ('En cours de livraison','Livrée') then return false; end if;
  select * into l from livreurs where actif
    and right(regexp_replace(tel,'\D','','g'),8) = right(regexp_replace(p_tel,'\D','','g'),8)
    and upper(code_acces) = upper(trim(p_code)) limit 1;
  if not found then return false; end if;
  update orders set statut = p_statut where code = p_order and livreur_id = l.id;
  get diagnostics n = row_count; return n > 0;
end $$;

grant execute on function public.livreur_orders(text,text) to anon, authenticated;
grant execute on function public.livreur_set_statut(text,text,text,text) to anon, authenticated;
