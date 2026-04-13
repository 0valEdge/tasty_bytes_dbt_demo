{{ config(materialized='semantic_view') }}

TABLES(
  order_header AS {{ ref('raw_pos_order_header') }} PRIMARY KEY (order_id),
  order_detail AS {{ ref('raw_pos_order_detail') }} PRIMARY KEY (order_detail_id),
  menu AS {{ ref('raw_pos_menu') }} PRIMARY KEY (menu_item_id),
  truck AS {{ ref('raw_pos_truck') }} PRIMARY KEY (truck_id),
  location AS {{ ref('raw_pos_location') }} PRIMARY KEY (location_id)
)
RELATIONSHIPS (
  OrderToDetail AS order_detail(order_id) REFERENCES order_header(order_id),
  DetailToMenu AS order_detail(menu_item_id) REFERENCES menu(menu_item_id),
  OrderToTruck AS order_header(truck_id) REFERENCES truck(truck_id),
  OrderToLocation AS order_header(location_id) REFERENCES location(location_id)
)
FACTS (
  order_detail.quantity AS quantity,
  order_detail.price AS price,
  order_header.order_amount AS order_amount,
  order_header.order_total AS order_total
)
DIMENSIONS (
  order_header.order_ts AS order_ts,
  order_header.order_channel AS order_channel,
  menu.menu_item_name AS menu_item_name,
  menu.item_category AS item_category,
  menu.truck_brand_name AS truck_brand_name,
  truck.primary_city AS primary_city,
  truck.country AS country,
  truck.ev_flag AS ev_flag,
  location.city AS city,
  location.region AS region
)
METRICS (
  order_detail.total_revenue AS SUM(order_detail.price),
  order_detail.total_quantity AS SUM(order_detail.quantity),
  order_header.avg_order_value AS AVG(order_header.order_total),
  order_header.max_order_total AS MAX(order_header.order_total)
)
COMMENT = 'Semantic view for order analytics'