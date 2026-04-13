{% snapshot customer_snapshot %}

{{
    config(
      target_schema='SNAPSHOTS',
      unique_key='customer_id',
      strategy='check',
      check_cols=[
        'first_name',
        'last_name',
        'e_mail',
        'phone_number',
        'city',
        'country'
      ]
    )
}}

SELECT
    customer_id,
    first_name,
    last_name,
    e_mail,
    phone_number,
    city,
    country
FROM {{ ref('customer_loyalty_metrics') }}

{% endsnapshot %}