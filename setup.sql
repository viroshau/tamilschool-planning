-- Timeplan for Anduvilla: databaseoppsett for Supabase
-- Kjør alt i SQL Editor. Har du kjørt en eldre versjon med PIN, kjør bare del 2 og 4.
-- NB: uten PIN kan alle som har lenken til siden endre timeplanen.

-- =====================================================================
-- Del 1: Tabeller
-- =====================================================================

create table location (
  id serial primary key,
  name text not null unique
);

create table teacher (
  id serial primary key,
  name text not null unique,
  color text not null default 'blue'   -- aqua, violet, orange, magenta, blue, green, red, yellow
);

create table song (
  id serial primary key,
  teacher_id int not null references teacher(id) on delete cascade,
  title text not null,
  unique (teacher_id, title)
);

create table slot (
  id serial primary key,
  location_id int not null references location(id) on delete cascade,
  date date not null,
  start_time time not null,
  end_time time not null,
  everyone boolean not null default false,  -- fellesøving: alle lærere, full gjennomgang av program
  note text                                 -- egen tekst på fellesøving, i stedet for standardteksten
);
create index slot_date_idx on slot (date);

create table assignment (
  slot_id int references slot(id) on delete cascade,
  song_id int references song(id) on delete cascade,
  created_at timestamptz default now(),
  primary key (slot_id, song_id)
);

-- =====================================================================
-- Del 2: Funksjoner (all skriving går gjennom disse)
-- Kan kjøres på nytt. Fjerner også PIN-oppsettet fra en tidligere versjon.
-- =====================================================================

drop function if exists pin_ok(int, text);
drop function if exists admin_ok(text);
drop function if exists set_teacher_pin(int, text, text);
drop function if exists assign_song(int, int, text);
drop function if exists unassign_song(int, int, text);
drop function if exists add_song(int, text, text);
drop function if exists add_teacher(text, text, text, text);
drop function if exists add_location(text, text);
drop function if exists create_slots(int, date, date, int[], time, time, text);
drop function if exists create_slots(int, date, date, int[], time, time);
drop function if exists delete_slot(int, text);
drop table if exists teacher_pin, admin_pin;

create or replace function assign_song(p_slot_id int, p_song_id int) returns void
language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from slot where id = p_slot_id and everyone) then
    raise exception 'Dette er fellesøving for alle – du trenger ikke legge inn sanger her';
  end if;
  insert into assignment (slot_id, song_id) values (p_slot_id, p_song_id) on conflict do nothing;
end $$;

create or replace function unassign_song(p_slot_id int, p_song_id int) returns void
language sql security definer set search_path = public as $$
  delete from assignment where slot_id = p_slot_id and song_id = p_song_id;
$$;

create or replace function add_song(p_teacher_id int, p_title text) returns int
language plpgsql security definer set search_path = public as $$
declare new_id int;
begin
  if length(trim(p_title)) = 0 then raise exception 'Sangen må ha en tittel'; end if;
  insert into song (teacher_id, title) values (p_teacher_id, trim(p_title)) returning id into new_id;
  return new_id;
end $$;

create or replace function rename_song(p_song_id int, p_title text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if length(trim(p_title)) = 0 then raise exception 'Sangen må ha en tittel'; end if;
  if exists (select 1 from song s join song o on o.teacher_id = s.teacher_id
             where s.id = p_song_id and o.id <> p_song_id and o.title = trim(p_title)) then
    raise exception 'Du har allerede en sang med det navnet';
  end if;
  update song set title = trim(p_title) where id = p_song_id;
end $$;

-- Fjerner også sangen fra alle økter den er lagt inn på
create or replace function delete_song(p_song_id int) returns void
language sql security definer set search_path = public as $$
  delete from song where id = p_song_id;
$$;

create or replace function add_teacher(p_name text, p_color text) returns int
language plpgsql security definer set search_path = public as $$
declare new_id int;
begin
  if length(trim(p_name)) = 0 then raise exception 'Læreren må ha et navn'; end if;
  insert into teacher (name, color) values (trim(p_name), p_color) returning id into new_id;
  return new_id;
end $$;

create or replace function add_location(p_name text) returns int
language plpgsql security definer set search_path = public as $$
declare new_id int;
begin
  if length(trim(p_name)) = 0 then raise exception 'Stedet må ha et navn'; end if;
  insert into location (name) values (trim(p_name)) returning id into new_id;
  return new_id;
end $$;

-- p_weekdays bruker ISO-ukedager: 1 = mandag ... 5 = fredag, 6 = lørdag, 7 = søndag
create or replace function create_slots(
  p_location_id int, p_from date, p_to date, p_weekdays int[],
  p_start time, p_end time, p_everyone boolean default false
) returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if p_to < p_from then raise exception 'Til-dato må være etter fra-dato'; end if;
  if p_end <= p_start then raise exception 'Slutt må være etter start'; end if;
  insert into slot (location_id, date, start_time, end_time, everyone)
  select p_location_id, d::date, p_start, p_end, p_everyone
  from generate_series(p_from, p_to, interval '1 day') d
  where extract(isodow from d) = any(p_weekdays);
  get diagnostics n = row_count;
  return n;
end $$;

create or replace function delete_slot(p_slot_id int) returns void
language sql security definer set search_path = public as $$
  delete from slot where id = p_slot_id;
$$;

grant execute on all functions in schema public to anon;

-- Be Supabase-API-et laste inn funksjonene på nytt
notify pgrst, 'reload schema';

-- =====================================================================
-- Del 3: Startdata fra notatboka
-- =====================================================================

insert into location (name) values ('Gausel'), ('Madla'), ('Lura');

insert into teacher (name, color) values
  ('Ajantha', 'aqua'), ('Casthoory', 'violet'), ('Priyanka', 'orange'),
  ('Abinaya', 'magenta'), ('Mala', 'blue'), ('Kanchana', 'green'),
  ('Keerthana', 'red');

-- Gausel: fredag 18–20, lørdag 11–14 (fellesøving), søndag 11–13, hver helg 30.10–20.12
insert into slot (location_id, date, start_time, end_time, everyone)
select (select id from location where name = 'Gausel'), d::date,
       case extract(isodow from d) when 5 then time '18:00' else time '11:00' end,
       case extract(isodow from d) when 5 then time '20:00' when 6 then time '14:00' else time '13:00' end,
       extract(isodow from d) = 6
from generate_series(date '2026-10-30', date '2026-12-20', interval '1 day') d
where extract(isodow from d) in (5, 6, 7);

-- Madla: to lørdagskvelder
insert into slot (location_id, date, start_time, end_time)
select (select id from location where name = 'Madla'), d, time '18:00', time '20:30'
from unnest(array[date '2026-11-07', date '2026-12-05']) d;

-- Sanger kan legges inn fra siden (Lærer-modus), eller her:
-- insert into song (teacher_id, title) select id, 'Tittel' from teacher where name = 'Mala';

-- =====================================================================
-- Del 4: Tilgang og sanntid (kan kjøres på nytt)
-- Besøkende kan lese tabellene direkte; endringer går via funksjonene i del 2.
-- =====================================================================

do $$
declare t text;
begin
  foreach t in array array['location', 'teacher', 'song', 'slot', 'assignment'] loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists read_all on %I', t);
    execute format('create policy read_all on %I for select to anon using (true)', t);
  end loop;
  foreach t in array array['assignment', 'slot', 'song'] loop
    if not exists (select 1 from pg_publication_tables
                   where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table %I', t);
    end if;
  end loop;
end $$;
