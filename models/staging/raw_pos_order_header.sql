{{ config(schema='STAGING') }}
SELECT *
FROM {{ source('tb_101', 'ORDER_HEADER') }}
