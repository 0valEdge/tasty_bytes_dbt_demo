{% macro dq_failure_records(results) %}

{% if execute %}

{{ log("========== DQ FAILURE RECORD CAPTURE STARTED ==========", info=True) }}

{% set central_tbl = target.database ~ '.' ~ target.schema ~ '.DQ_FAILED_RECORDS' %}

{# Aggregate tests (no row-level failures) #}
{% set aggregate_tests = [
    'equal_rowcount',
    'fewer_rows_than',
    'recency',
    'expression_is_true'
] %}

{# Prevent duplicate processing #}
{% set processed = [] %}

{% for result in results %}

    {# ✅ Only data failures (fail + warn), exclude execution errors #}
    {% if result.node.resource_type != 'test'
        or result.status not in ['fail', 'warn']
        or result.failures is none
        or result.failures <= 0 %}
        {% continue %}
    {% endif %}

    {% set node = result.node %}
    {% set test_name = node.name %}
    {% set test_unique_id = node.unique_id %}
    {% set test_type = node.test_metadata.name if node.test_metadata is defined else '' %}
    {% set severity = node.config.severity if node.config is defined else 'error' %}
    {% set failure_relation = node.relation_name %}

    {# Skip aggregate tests #}
    {% if test_type in aggregate_tests %}
        {{ log("⚠️ Skipping aggregate test: " ~ test_name, info=True) }}
        {% continue %}
    {% endif %}

    {# Prevent duplicates #}
    {% if test_unique_id in processed %}
        {% continue %}
    {% endif %}
    {% do processed.append(test_unique_id) %}

    {{ log("---- Processing failed test: " ~ test_name ~ " | severity: " ~ severity, info=True) }}

    {# Validate relation exists #}
    {% if not failure_relation %}
        {{ log("❌ No failure relation for: " ~ test_name, info=True) }}
        {% continue %}
    {% endif %}

    {# Check failure row count #}
    {% set count_query %}
        select count(*) from {{ failure_relation }}
    {% endset %}

    {% set count_result = run_query(count_query) %}
    {% set failure_rows = count_result.rows[0][0] if count_result and count_result.rows else 0 %}

    {% if failure_rows == 0 %}
        {{ log("⚠️ Empty failure table, skipping: " ~ failure_relation, info=True) }}
        {% continue %}
    {% endif %}

    {{ log("✔ Failure rows: " ~ failure_rows, info=True) }}

    {# Insert into central table #}
    {% set insert_sql %}
        insert into {{ central_tbl }}
        (
            run_id,
            test_name,
            test_unique_id,
            test_type,
            severity,
            failure_count,
            test_failures_json,
            executed_at
        )
        select
            '{{ invocation_id }}',
            '{{ test_name }}',
            '{{ test_unique_id }}',
            '{{ test_type }}',
            '{{ severity }}',
            {{ failure_rows }},
            object_construct_keep_null(*),
            current_timestamp
        from {{ failure_relation }}
    {% endset %}

    {% do run_query(insert_sql) %}

    {{ log("✔ Inserted failures for: " ~ test_name, info=True) }}

{% endfor %}

{{ log("========== DQ FAILURE RECORD CAPTURE COMPLETED ==========", info=True) }}

{% endif %}

{% endmacro %}