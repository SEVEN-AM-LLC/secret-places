-- "Suggest a place": signed-in users send places from their city to an editors' queue.
-- Nothing is published automatically — an editor reviews each submission (state) and,
-- if it's good, adds it to public.places by hand.

alter table public.submissions
  add column if not exists city_id uuid references public.cities(id) on delete set null,
  add column if not exists address text;

-- Deleting an account removes the user's suggestions too (delete-account relies on cascades).
alter table public.submissions drop constraint if exists submissions_user_id_fkey;
alter table public.submissions
  add constraint submissions_user_id_fkey foreign key (user_id) references auth.users(id) on delete cascade;

alter table public.submissions
  add constraint submissions_title_len check (char_length(btrim(title)) between 2 and 120),
  add constraint submissions_text_len check (char_length(coalesce(description, '')) <= 2000
                                             and char_length(coalesce(why_special, '')) <= 2000
                                             and char_length(coalesce(tips, '')) <= 2000
                                             and char_length(coalesce(address, '')) <= 300),
  add constraint submissions_coords check ((lat is null or lat between -90 and 90) and (lng is null or lng between -180 and 180));

create index if not exists submissions_state_created_idx on public.submissions (state, created_at desc);

-- Users only create fresh submissions and read their own; review state belongs to editors.
drop policy if exists submissions_insert on public.submissions;
drop policy if exists submissions_update on public.submissions;
create policy submissions_insert on public.submissions for insert
  with check (auth.uid() = user_id and state = 'submitted');
revoke update, delete on public.submissions from authenticated, anon;

-- Light abuse guard: at most 10 suggestions per user per day.
create or replace function public.submissions_rate_limit() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from public.submissions
      where user_id = new.user_id and created_at > now() - interval '1 day') >= 10 then
    raise exception 'too_many_suggestions' using errcode = 'P0001';
  end if;
  return new;
end $$;

drop trigger if exists submissions_rate_limit on public.submissions;
create trigger submissions_rate_limit before insert on public.submissions
  for each row execute function public.submissions_rate_limit();
