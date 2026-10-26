-- A custom GENERIC test. Attach it to any numeric column in a YAML file:
--   data_tests:
--     - value_between:
--         arguments: {min_value: 0, max_value: 1}
-- It returns the offending rows. Zero rows returned means the test passes.
{% test value_between(model, column_name, min_value, max_value) %}

select {{ column_name }} as offending_value
from {{ model }}
where {{ column_name }} is not null
  and ({{ column_name }} < {{ min_value }} or {{ column_name }} > {{ max_value }})

{% endtest %}