-- Create helper views derived from existing arrays on match_records
-- Drop conflicting relations first (tables or views), then create views

drop view if exists match_pet_talent_v cascade;
create view match_pet_talent_v as
select
  mr.id as match_id,
  pet.pet_id,
  coalesce(mr.spirit_animal_talents[pet.idx], 0) as talent_value
from match_records mr
cross join lateral unnest(mr.spirit_animal) with ordinality as pet(pet_id, idx)
where pet.pet_id is not null;

drop view if exists match_rune_v cascade;
create view match_rune_v as
select mr.id as match_id, rune.rune_id
from match_records mr
cross join lateral unnest(mr.legendary_runes) as rune(rune_id)
where rune.rune_id is not null;


