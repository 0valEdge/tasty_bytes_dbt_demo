{% macro dqstats_log_results(results) %}
{% if execute %}

{{ log("========== DQ LOGGING STARTED ==========", info=True) }}

{% set run_id = invocation_id %}
{% set dbt_project_name = project_name %}

{# Prevent duplicate inserts #}
{% set processed = [] %}

{% for res in results %}

    {% if res.node.resource_type != 'test' %}
        {% continue %}
    {% endif %}

    {% set node = res.node %}
    {% set status = res.status %}
    {% set test_name = node.name %}
    {% set failed_count = (res.failures | int) if res.failures is not none else 0 %}
    {% set test_unique_id = node.unique_id %}

    {# Column name extraction #}
    {% set column_name = '' %}
    {% if node.test_metadata is defined and node.test_metadata.kwargs is defined %}
        {% if node.test_metadata.kwargs.column_name is defined %}
            {% set column_name = node.test_metadata.kwargs.column_name %}
        {% elif node.test_metadata.kwargs.arg is defined %}
            {% set column_name = node.test_metadata.kwargs.arg %}
        {% endif %}
    {% endif %}

    {# Test type #}
    {% set test_type = node.test_metadata.name if node.test_metadata is defined else '' %}

    {# YML file #}
    {% set yml_file_name = node.original_file_path.split('/')[-1] if node.original_file_path else '' %}

    {{ log("---- Processing Test: " ~ test_name, info=True) }}

    {% for parent in node.depends_on.nodes %}

        {# Unique key to avoid duplicates #}
        {% set unique_key = test_unique_id ~ '|' ~ parent %}
        {% if unique_key in processed %}
            {% continue %}
        {% endif %}
        {% do processed.append(unique_key) %}

        {% set parent_node = graph.nodes.get(parent) %}
        {% set source_node = graph.sources.get(parent) %}

        {% set resource_type = '' %}
        {% set object_name = '' %}
        {% set database_name = '' %}
        {% set schema_name = '' %}
        {% set model_id = parent %}

        {# ✅ MODEL / SEED / SNAPSHOT #}
        {% if parent_node %}

            {% if parent_node.resource_type in ['model', 'seed', 'snapshot'] %}

                {# Skip ephemeral #}
                {% if parent_node.config.materialized == 'ephemeral' %}
                    {{ log("⚠️ Skipping ephemeral: " ~ parent_node.name, info=True) }}
                    {% continue %}
                {% endif %}

                {% set resource_type = parent_node.resource_type %}
                {% set object_name = parent_node.alias %}
                {% set database_name = parent_node.database %}
                {% set schema_name = parent_node.schema %}
                {% set model_id = parent_node.unique_id %}

                {{ log("✅ " ~ resource_type | upper ~ ": " ~ object_name, info=True) }}

            {% endif %}

        {# ✅ SOURCE #}
        {% elif source_node %}

            {% set resource_type = 'source' %}
            {% set object_name = source_node.name %}
            {% set database_name = source_node.database %}
            {% set schema_name = source_node.schema %}
            {% set model_id = source_node.unique_id %}

            {{ log("✅ SOURCE: " ~ schema_name ~ "." ~ object_name, info=True) }}

        {% else %}
            {{ log("❌ Unknown parent: " ~ parent, info=True) }}
            {% continue %}
        {% endif %}

        {# Ensure required values #}
        {% if not object_name or not database_name or not schema_name %}
            {{ log("⚠️ Missing metadata, skipping: " ~ parent, info=True) }}
            {% continue %}
        {% endif %}

        {# Get relation safely #}
        {% set relation = adapter.get_relation(
            database=database_name,
            schema=schema_name,
            identifier=object_name
        ) %}

        {% if relation is none %}
            {{ log("❌ Relation not found: " ~ database_name ~ "." ~ schema_name ~ "." ~ object_name, info=True) }}
            {% continue %}
        {% endif %}

        {# Get total count safely #}
        {% set total_count = 0 %}
        {% set total_query %}
            select count(*) as row_count from {{ relation }}
        {% endset %}

        {% set total_result = run_query(total_query) %}

        {% if total_result and total_result.rows and (total_result.rows | length) > 0 %}
            {% set total_count = total_result.rows[0][0] %}
        {% endif %}

        {% set passed_count = [total_count - failed_count, 0] | max %}

        {# Insert #}
        {% set insert_sql %}
            insert into {{ target.database }}.{{ target.schema }}.DQ_STATS
            (
                run_id, dbt_project_name, model_id, resource_type,
                yml_file_name, database_name, schema_name, table_name,
                column_name, test_name, test_unique_id, test_type,
                total_row_count, failed_row_count, passed_row_count,
                status, executed_at
            )
            values (
                '{{ run_id }}',
                '{{ dbt_project_name }}',
                '{{ model_id }}',
                '{{ resource_type }}',
                '{{ yml_file_name }}',
                '{{ database_name }}',
                '{{ schema_name }}',
                '{{ object_name }}',
                '{{ column_name }}',
                '{{ test_name }}',
                '{{ test_unique_id }}',
                '{{ test_type }}',
                {{ total_count }},
                {{ failed_count }},
                {{ passed_count }},
                '{{ status }}',
                current_timestamp
            )
        {% endset %}

        {% do run_query(insert_sql) %}

        {{ log("✔ Inserted: " ~ object_name ~ " | Test: " ~ test_name, info=True) }}

    {% endfor %}

{% endfor %}

{{ log("========== DQ LOGGING COMPLETED ==========", info=True) }}

{% endif %}
{% endmacro %}