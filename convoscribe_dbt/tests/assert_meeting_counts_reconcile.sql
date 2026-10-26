-- Rule: staged meetings = meetings in fct_meetings + meetings deliberately excluded.
-- Proves nothing was silently lost. Returns a row only if the numbers don't add up.

with counts as (

    select
        (select count(*) from {{ ref('stg_meetings') }}) as staged,
        (select count(*) from {{ ref('fct_meetings') }}) as in_mart,
        (
            select count(*)
            from {{ ref('stg_meetings') }} as m
            left join {{ ref('stg_users') }} as u on u.user_id = m.user_id
            where not m.is_valid_duration   -- excluded: bad duration
               or u.user_id is null         -- excluded: unknown user
        ) as excluded

)

select *
from counts
where staged <> in_mart + excluded