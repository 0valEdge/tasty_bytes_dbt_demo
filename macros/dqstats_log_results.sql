{% macro dqstats_log_results(results) %}
{% if execute %}

{{ log("========== DQ LOGGING STARTED ==========", info=True) }}

{% set run_id = invocation_id %}
{% set dbt_project_name = project_name %}

{# Prevent duplicate inserts. Using a plain list + 'in' check (no {% continue %} needed). #}
{% set processed = [] %}

{% for res in results %}
{# Generic/singular data tests have resource_type 'test'; unit tests have resource_type 'unit_test'. #}
{% if res.node.resource_type in ['test', 'unit_test'] %}

    {% set node = res.node %}
    {% set status = res.status %}
    {% set test_name = node.name %}
    {% set is_unit_test = (node.resource_type == 'unit_test') %}
    {% set failed_count = (res.failures | int) if res.failures is not none else 0 %}
    {% set test_unique_id = node.unique_id %}

    {# Column name extraction — only meaningful for generic data tests (e.g. not_null on a
       column). Unit tests validate a whole model against fixtures, so there's no single
       column; column_name is left blank for those. #}
    {% set column_name = '' %}
    {% if not is_unit_test and node.test_metadata is defined and node.test_metadata.kwargs is defined %}
        {% if node.test_metadata.kwargs.column_name is defined %}
            {% set column_name = node.test_metadata.kwargs.column_name %}
        {% elif node.test_metadata.kwargs.arg is defined %}
            {% set column_name = node.test_metadata.kwargs.arg %}
        {% endif %}
    {% endif %}

    {# Test type #}
    {% if is_unit_test %}
        {% set test_type = 'unit_test' %}
    {% else %}
        {% set test_type = node.test_metadata.name if node.test_metadata is defined else '' %}
    {% endif %}

    {# YML file #}
    {% set yml_file_name = node.original_file_path.split('/')[-1] if node.original_file_path else '' %}

    {{ log("---- Processing " ~ ('Unit Test' if is_unit_test else 'Test') ~ ": " ~ test_name, info=True) }}

    {% for parent in node.depends_on.nodes %}

        {# Unique key to avoid duplicates #}
        {% set unique_key = test_unique_id ~ '|' ~ parent %}

        {% if unique_key not in processed %}
        {% do processed.append(unique_key) %}

        {# Mutable state across nested if-blocks. Fusion's minijinja doesn't reliably
           support {% continue %} / {% break %} (loopcontrols extension), so instead of
           short-circuiting the loop iteration, we use a namespace flag and gate all
           downstream logic behind it. #}
        {% set ns = namespace(
            valid=false,
            resource_type='',
            object_name='',
            database_name='',
            schema_name='',
            model_id=parent
        ) %}

        {% set parent_node = graph.nodes.get(parent) %}
        {% set source_node = graph.sources.get(parent) %}

        {# MODEL / SEED / SNAPSHOT #}
        {% if parent_node %}

            {% if parent_node.resource_type in ['model', 'seed', 'snapshot'] %}

                {% if parent_node.config.materialized == 'ephemeral' %}
                    {{ log("Skipping ephemeral: " ~ parent_node.name, info=True) }}
                {% else %}
                    {% set ns.valid = true %}
                    {% set ns.resource_type = parent_node.resource_type %}
                    {% set ns.object_name = parent_node.alias %}
                    {% set ns.database_name = parent_node.database %}
                    {% set ns.schema_name = parent_node.schema %}
                    {% set ns.model_id = parent_node.unique_id %}

                    {{ log(ns.resource_type | upper ~ ": " ~ ns.object_name, info=True) }}
                {% endif %}

            {% endif %}

        {# SOURCE #}
        {% elif source_node %}

            {% set ns.valid = true %}
            {% set ns.resource_type = 'source' %}
            {% set ns.object_name = source_node.name %}
            {% set ns.database_name = source_node.database %}
            {% set ns.schema_name = source_node.schema %}
            {% set ns.model_id = source_node.unique_id %}

            {{ log("SOURCE: " ~ ns.schema_name ~ "." ~ ns.object_name, info=True) }}

        {% else %}
            {{ log("Unknown parent: " ~ parent, info=True) }}
        {% endif %}

        {# Ensure required values, then do all the DB work under one guard #}
        {% if ns.valid and ns.object_name and ns.database_name and ns.schema_name %}

            {# Get relation safely #}
            {% set relation = adapter.get_relation(
                database=ns.database_name,
                schema=ns.schema_name,
                identifier=ns.object_name
            ) %}

            {% if relation is none %}
                {{ log("Relation not found: " ~ ns.database_name ~ "." ~ ns.schema_name ~ "." ~ ns.object_name, info=True) }}
            {% else %}

                {% if is_unit_test %}
                    {# Unit tests run against static fixture data, not the live relation, so
                       "row counts" don't apply — dbt only reports pass/fail. Represent that
                       as a single-row outcome (1 total, 0 or 1 failed) so it fits the same
                       DQ_STATS schema as row-level tests. #}
                    {% set total_count = 1 %}
                    {% set failed_count = 0 if status in ['pass', 'success'] else 1 %}
                    {% set passed_count = 1 - failed_count %}
                {% else %}
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
                {% endif %}

                {# Escape single quotes so identifiers/names with apostrophes don't break the insert #}
                {% set esc = dqstats_escape_sql %}

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
                        '{{ esc(run_id) }}',
                        '{{ esc(dbt_project_name) }}',
                        '{{ esc(ns.model_id) }}',
                        '{{ esc(ns.resource_type) }}',
                        '{{ esc(yml_file_name) }}',
                        '{{ esc(ns.database_name) }}',
                        '{{ esc(ns.schema_name) }}',
                        '{{ esc(ns.object_name) }}',
                        '{{ esc(column_name) }}',
                        '{{ esc(test_name) }}',
                        '{{ esc(test_unique_id) }}',
                        '{{ esc(test_type) }}',
                        {{ total_count }},
                        {{ failed_count }},
                        {{ passed_count }},
                        '{{ esc(status) }}',
                        current_timestamp
                    )
                {% endset %}

                {% do run_query(insert_sql) %}

                {{ log("Inserted: " ~ ns.object_name ~ " | " ~ ('Unit Test' if is_unit_test else 'Test') ~ ": " ~ test_name, info=True) }}

            {% endif %}

        {% elif ns.resource_type or ns.object_name %}
            {# We identified a resource_type/parent but metadata was incomplete #}
            {{ log("Missing metadata, skipping: " ~ parent, info=True) }}
        {% endif %}

        {% endif %} {# unique_key not in processed #}

    {% endfor %}

{% endif %}
{% endfor %}

{{ log("========== DQ LOGGING COMPLETED ==========", info=True) }}

{% endif %}
{% endmacro %}


{# Small helper macro: escapes single quotes for safe interpolation into SQL string literals.
   Keeping this as its own macro (rather than a Jinja filter chain) makes it easy to unit-test
   and reuse elsewhere in the project. #}
{% macro dqstats_escape_sql(value) %}
{{ return((value or '') | replace("'", "''")) }}
{% endmacro %}