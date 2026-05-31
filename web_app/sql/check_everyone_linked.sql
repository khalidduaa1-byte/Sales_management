-- =============================================================================
-- One-page health check — run in Supabase SQL Editor
-- =============================================================================

-- 1) Excel imports still waiting for an account? (should be 0 rows or only names not signed up)
select ba_name, team, count(*) as unlinked_sales
from public.sales_entries
where ba_id is null
  and trim(coalesce(ba_name, '')) <> ''
group by ba_name, team
order by unlinked_sales desc, ba_name;

-- 2) Auth users without profile (login = "Profile not found")
select u.id, u.email, u.email_confirmed_at is not null as confirmed
from auth.users u
left join public.profiles p on p.id = u.id
where p.id is null
order by u.email;

-- 3) Unconfirmed email (can't sign in if confirm required)
select u.email, p.name, u.created_at::date
from auth.users u
left join public.profiles p on p.id = u.id
where u.email_confirmed_at is null
order by u.created_at desc;

-- 4) Each BA: linked sales count + May total
select
  p.name,
  p.team,
  u.email,
  u.email_confirmed_at is not null as confirmed,
  count(s.id) as linked_sales,
  coalesce(sum(s.sales_amount) filter (
    where s.entry_date >= '2026-05-01' and s.entry_date < '2026-06-01'
  ), 0) as may_total
from public.profiles p
left join auth.users u on u.id = p.id
left join public.sales_entries s on s.ba_id = p.id
where p.role = 'ba'
group by p.id, p.name, p.team, u.email, u.email_confirmed_at
order by p.team, p.name;

-- 5) Registered but 0 linked (signed up wrong name or link not run)
select p.name, p.team, u.email, count(s.id) as linked_sales
from public.profiles p
join auth.users u on u.id = p.id
left join public.sales_entries s on s.ba_id = p.id
where p.role = 'ba'
group by p.id, p.name, p.team, u.email
having count(s.id) = 0
order by p.name;
