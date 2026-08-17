-- macros/get_parameter.sql
{% macro get_param(param_name) %}
    {% set env = target.name %}  {# e.g. 'prt' or 'prd' #}
    {% set query %}
        select parameter_value
        from {{ ref(env ~ '_parameters') }}
        where parameter_name = '{{ param_name }}'
    {% endset %}
    {% if execute %}
        {% set result = run_query(query) %}
        {{ return(result.columns[0].values()[0]) }}
    {% else %}
        {{ return('') }}
    {% endif %}
{% endmacro %}