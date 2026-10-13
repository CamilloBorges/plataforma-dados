{#- O schema configurado (+schema) é usado como está ("stg", "api"), sem o prefixo do target. -#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {{ custom_schema_name | trim if custom_schema_name else target.schema }}
{%- endmacro %}
