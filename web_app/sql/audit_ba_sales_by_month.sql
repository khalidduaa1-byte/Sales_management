-- Audit BA sales vs target (e.g. Mamdouh Mohamed — 110% complaint)
-- Replace the name in the filter below, then run in Supabase SQL Editor.

-- 1) Profile + team
select p.id, p.name, p.team, u.email
from public.profiles p
left join auth.users u on u.id = p.id
where p.role = 'ba'
  and public.normalize_ba_name(p.name) = public.normalize_ba_name('Mamdouh Mohamed');

-- 2) Sales by month (should explain which month drives the % bar)
select
  to_char(s.entry_date::date, 'YYYY-MM') as month,
  count(*) as rows,
  sum(s.sales_amount)::numeric(12,2) as total_sales,
  sum(s.items_sold) as total_pcs
from public.sales_entries s
join public.profiles p on p.id = s.ba_id
where public.normalize_ba_name(p.name) = public.normalize_ba_name('Mamdouh Mohamed')
group by 1
order by 1;

-- 3) May 2026 detail (current month on BA app)
select s.entry_date, s.store, s.shift, s.sales_amount, s.items_sold, s.created_at
from public.sales_entries s
join public.profiles p on p.id = s.ba_id
where public.normalize_ba_name(p.name) = public.normalize_ba_name('Mamdouh Mohamed')
  and s.entry_date between '2026-05-01' and '2026-05-31'
order by s.entry_date, s.store;

-- 4) April 2026 (Excel import — he did not type these in the app)
select s.entry_date, s.store, s.shift, s.sales_amount, s.items_sold
from public.sales_entries s
join public.profiles p on p.id = s.ba_id
where public.normalize_ba_name(p.name) = public.normalize_ba_name('Mamdouh Mohamed')
  and s.entry_date between '2026-04-01' and '2026-04-30'
order by s.entry_date;

-- 5) Duplicate same day / shop / shift (double-count risk)
select s.entry_date, s.store, s.shift, count(*) as cnt, sum(s.sales_amount) as total
from public.sales_entries s
join public.profiles p on p.id = s.ba_id
where public.normalize_ba_name(p.name) = public.normalize_ba_name('Mamdouh Mohamed')
group by s.entry_date, s.store, s.shift
having count(*) > 1
order by s.entry_date;

-- 6) Target for his team (May) — small goal + high imports => high %
select *
from public.monthly_targets
where team = 'Sharm'
  and month_key = '2026-05';
