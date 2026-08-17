SELECT 
    cl.customer_id,
    cl.city,
    cl.country,
    cl.first_name,
    cl.last_name,
    cl.phone_number,
    cl.e_mail,
    SUM(oh.order_total) AS total_sales,
    ARRAY_AGG(DISTINCT oh.location_id) AS visited_location_ids_array
FROM {{get_param('P_STG_DATABASE')}}.{{get_param('P_STG_EDW_SCHEMA')}}.raw_customer_customer_loyalty cl
JOIN {{get_param('P_STG_DATABASE')}}.{{get_param('P_STG_EDW_SCHEMA')}}. raw_pos_order_header oh
ON cl.customer_id = oh.customer_id
GROUP BY cl.customer_id, cl.city, cl.country, cl.first_name,
cl.last_name, cl.phone_number, cl.e_mail