{% test valid_phone(model, column_name) %}

SELECT *
FROM {{ model }}
WHERE {{ column_name }} IS NOT NULL
  AND NOT REGEXP_LIKE({{ column_name }},
      '^[0-9]{10}$')   -- adjust for country format

{% endtest %}