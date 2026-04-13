{% materialization semantic_view, adapter='snowflake' %}

  {% set compiled_sql = model['compiled_sql'] %}

  {% set sql %}
    CREATE OR REPLACE SEMANTIC VIEW {{ this }} AS
    {{ compiled_sql }}
  {% endset %}

  {% do run_query(sql) %}

  {{ return({'relations': [this]}) }}

{% endmaterialization %}