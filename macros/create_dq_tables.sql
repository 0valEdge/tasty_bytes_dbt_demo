{% macro create_dq_tables() %}
{% if execute %}

    {{ log("Recreating DQ_STATS table", info=True) }}

    {% set create_sql %}
        create or replace table {{ target.database }}.{{ target.schema }}.DQ_STATS (
            run_id                string,
            dbt_project_name      string,
            model_id              string,
            resource_type         string,
            yml_file_name         string,
            database_name         string,
            schema_name           string,
            table_name            string,
            column_name           string,
            test_name             string,
            test_unique_id        string,
            test_type             string,
            total_row_count       number,
            failed_row_count      number,
            passed_row_count      number,
            status                string,
            executed_at           timestamp
        );
    {% endset %}

    {% do run_query(create_sql) %}

    {{ log("DQ_STATS table recreated successfully", info=True) }}

{% endif %}
{% endmacro %}
