--USE online_shop;

--count of customers by states
SELECT RIGHT(address, 2) AS state, COUNT(customer_id) AS count
FROM customers
GROUP BY RIGHT(address, 2);



--revenue by date
SELECT order_date, COUNT(customer_id) AS customers, SUM(total_price) AS revenue
FROM orders
GROUP BY order_date;



--revenue by product
SELECT p.product_id, SUM(oi.quantity) AS quantity, SUM(oi.quantity*oi.price_at_purchase) AS revenue
FROM order_items oi JOIN products p ON oi.product_id = p.product_id
GROUP BY p.product_id;
--revenue by type of product
SELECT p.product_name, SUM(oi.quantity) AS quantity, SUM(oi.quantity*oi.price_at_purchase) AS revenue
FROM order_items oi JOIN products p ON oi.product_id = p.product_id
GROUP BY p.product_name;
--revenue by product category
SELECT p.category, SUM(oi.quantity) AS quantity, SUM(oi.quantity*oi.price_at_purchase) AS revenue
FROM order_items oi JOIN products p ON oi.product_id = p.product_id
GROUP BY p.category;
--revenue by supplier
SELECT p.supplier_id, SUM(oi.quantity) AS quantity, SUM(oi.quantity*oi.price_at_purchase) AS revenue
FROM order_items oi JOIN products p ON oi.product_id = p.product_id
GROUP BY p.supplier_id;



--count of suppliers by state
SELECT RIGHT(address, 2) AS state, COUNT(supplier_id) AS count
FROM suppliers
GROUP BY RIGHT(address, 2);



--shipments by status
SELECT shipment_status, COUNT(shipment_id) AS count
FROM shipments
GROUP BY shipment_status;
--shipments by status and carrier
SELECT shipment_status, carrier, COUNT(shipment_id) AS count
FROM shipments
GROUP BY shipment_status, carrier
ORDER BY shipment_status;



--amount by transaction status
SELECT transaction_status, SUM(amount) AS amount
FROM payment
GROUP BY transaction_status;



DROP TABLE IF EXISTS rfm_segments;


WITH rfm_base AS (
	SELECT customer_id, MAX(order_date) AS last_purchase_date, COUNT(order_id) AS frequency, SUM(total_price) AS monetary
	FROM orders
	GROUP BY customer_id),
rfm_scored AS (
	SELECT customer_id, 
	last_purchase_date, frequency, monetary,
	NTILE(5) OVER (ORDER BY last_purchase_date ASC) AS recency_score,
	NTILE(5) OVER (ORDER BY frequency ASC) AS frequency_score,
	NTILE(5) OVER (ORDER BY monetary ASC) AS monetary_score
	FROM rfm_base
	)
SELECT customer_id, last_purchase_date, frequency, monetary, recency_score, frequency_score, monetary_score,
CONCAT(recency_score, frequency_score, monetary_score) AS rfm_score
INTO rfm_segments
FROM rfm_scored;




--add segment column
ALTER TABLE rfm_segments
ADD customer_segment NVARCHAR(50);



UPDATE rfm_segments
SET customer_segment = 
    CASE
        -- LOYAL (Champions)
        WHEN rfm_score IN ('555', '554', '545', '544', '454', '455', '445') THEN 'Champions'
        
        -- LOYAL (Loyal Customers)
        WHEN rfm_score IN ('543', '444', '443', '355', '354', '345', '344', '335') THEN 'Loyal'
        
        -- LOYAL (Potential Loyalists)
        WHEN rfm_score IN ('553', '551', '552', '541', '542', '533', '532', '531', '452', '451',
                             '442', '441', '431', '453', '433', '423', '342', '341', '333', '323') THEN 'Potential_Loyalist'
                             
        -- PROMISING (Recent Customers)
        WHEN rfm_score IN ('512', '511', '422', '421', '412', '411', '311') THEN 'Recent_Customers'
        
        -- PROMISING (Promising)
        WHEN rfm_score IN ('525', '524', '523', '522', '521', '515', '514', '513', '425', '424',
                             '413', '414', '415', '315', '314', '313') THEN 'Promising'
                             
        -- PROMISING (Need Attention)
        WHEN rfm_score IN ('535', '534', '443', '434', '343', '334', '325', '324') THEN 'Need_Attention'
        
        -- SLEEP (About to Sleep)
        WHEN rfm_score IN ('331', '321', '312', '221', '213', '231', '241', '251') THEN 'About_to_Sleep'
        
        -- SLEEP (At Risk)
        WHEN rfm_score IN ('255', '254', '245', '244', '253', '252', '243', '242', '235',
                             '224', '225', '143', '152', '134', '133', '125', '124') THEN 'At_Risk'
                             
        -- SLEEP (Cannot Lose)
        WHEN rfm_score IN ('155', '154', '144', '214', '215', '115', '114', '113') THEN 'Cannot_Lose'
        
        -- LOST (Hibernating)
        WHEN rfm_score IN ('332', '322', '231', '241', '251', '233', '232', '223', '222',
                             '132', '123', '122', '212', '211') THEN 'Hibernating'
                             
        -- LOST (Lost)
        WHEN rfm_score IN ('111', '112', '121', '131', '141', '151') THEN 'Lost'
        
        -- Default fallback for unmatched segments
        ELSE 'Uncategorized'
    END;



--number of customers by segment
SELECT customer_segment, COUNT(customer_id) AS count, SUM(monetary) AS revenue, AVG(frequency) AS avg_frequency
FROM rfm_segments
GROUP BY customer_segment;





--calculate CLV
WITH CLV_CALC AS (
	SELECT AVG(total_price) AS average_order_value, COUNT(order_id)/CAST(COUNT(DISTINCT customer_id) AS float) AS purchase_frequency
	FROM orders)
SELECT average_order_value, purchase_frequency, average_order_value * purchase_frequency AS CLV FROM CLV_CALC;



--check reviews rating - product - category
SELECT product_name, SUM(rating)/CAST(COUNT(review_id) AS float) AS average_rating, COUNT(review_id) AS reviews
FROM reviews r JOIN products p ON r.product_id = p.product_id
GROUP BY product_name; 

SELECT category, SUM(rating)/CAST(COUNT(review_id) AS float) AS average_rating, COUNT(review_id) AS reviews
FROM reviews r JOIN products p ON r.product_id = p.product_id
GROUP BY category; 



--calculate discount amount - product - category
--group by product_name
With discount_base AS (
	SELECT oi.order_id, oi.product_id, p.product_name, p.category, oi.quantity, o.total_price, oi.price_at_purchase, p.price, (p.price - oi.price_at_purchase)*oi.quantity AS discounted_amount, (p.price - oi.price_at_purchase)*oi.quantity/o.total_price AS discount_over_order
	FROM order_items oi JOIN products p ON oi.product_id = p.product_id JOIN orders o ON o.order_id = oi.order_id)
SELECT product_name, SUM(discounted_amount) AS discounted_amount, AVG(discount_over_order) AS discount_over_order
FROM discount_base
GROUP BY product_name;

--group by category
With discount_base AS (
	SELECT oi.order_id, oi.product_id, p.product_name, p.category, oi.quantity, o.total_price, oi.price_at_purchase, p.price, (p.price - oi.price_at_purchase)*oi.quantity AS discounted_amount, (p.price - oi.price_at_purchase)*oi.quantity/o.total_price AS discount_over_order
	FROM order_items oi JOIN products p ON oi.product_id = p.product_id JOIN orders o ON o.order_id = oi.order_id)
SELECT category, SUM(discounted_amount) AS discounted_amount, AVG(discount_over_order) AS discount_over_order
FROM discount_base
GROUP BY category;


--group by date
With discount_base AS (
	SELECT o.order_date, oi.order_id, oi.product_id, p.product_name, p.category, oi.quantity, o.total_price, oi.price_at_purchase, p.price, (p.price - oi.price_at_purchase)*oi.quantity AS discounted_amount, (p.price - oi.price_at_purchase)*oi.quantity/o.total_price AS discount_over_order
	FROM order_items oi JOIN products p ON oi.product_id = p.product_id JOIN orders o ON o.order_id = oi.order_id)
SELECT order_date, SUM(discounted_amount) AS discounted_amount, AVG(discount_over_order) AS discount_over_order
FROM discount_base
GROUP BY order_date
ORDER BY order_date ASC;




--fee or coupon after order by carrier
With payment_base AS (
	SELECT o.order_id, o.total_price, p.amount, (p.amount - o.total_price) AS fee_or_coupon_amount, p.amount/o.total_price AS paid_over_order, s.carrier, s.shipment_status , p.transaction_status
	FROM orders o JOIN payment p ON o.order_id = p.order_id JOIN shipments s ON o.order_id = s.order_id)
SELECT carrier, SUM(total_price) AS total_price, SUM(amount) AS final_amount, SUM(fee_or_coupon_amount) AS fee_or_coupon_amount, AVG(paid_over_order) AS avg_paid_over_order, SUM(amount)/SUM(total_price) as final_amount_over_total_price
FROM payment_base
GROUP BY carrier;


--fee or coupon after order by shipment_status
With payment_base AS (
	SELECT o.order_id, o.total_price, p.amount, (p.amount - o.total_price) AS fee_or_coupon_amount, p.amount/o.total_price AS paid_over_order, s.carrier, s.shipment_status , p.transaction_status
	FROM orders o JOIN payment p ON o.order_id = p.order_id JOIN shipments s ON o.order_id = s.order_id)
SELECT shipment_status, SUM(total_price) AS total_price, SUM(amount) AS final_amount, SUM(fee_or_coupon_amount) AS fee_or_coupon_amount, AVG(paid_over_order) AS avg_paid_over_order, SUM(amount)/SUM(total_price) as final_amount_over_total_price
FROM payment_base
GROUP BY shipment_status;



--fee or coupon after order by transaction status
With payment_base AS (
	SELECT o.order_id, o.total_price, p.amount, (p.amount - o.total_price) AS fee_or_coupon_amount, p.amount/o.total_price AS paid_over_order, s.carrier, s.shipment_status , p.transaction_status
	FROM orders o JOIN payment p ON o.order_id = p.order_id JOIN shipments s ON o.order_id = s.order_id)
SELECT transaction_status, SUM(total_price) AS total_price, SUM(amount) AS final_amount, SUM(fee_or_coupon_amount) AS fee_or_coupon_amount, AVG(paid_over_order) AS avg_paid_over_order, SUM(amount)/SUM(total_price) as final_amount_over_total_price
FROM payment_base
GROUP BY transaction_status;



--shipment time
SELECT TOP 100 carrier, shipment_status, CONCAT(AVG(DATEDIFF(DAY, shipment_date, delivery_date)), ' days') AS avg_shipping_time
FROM shipments
GROUP BY carrier, shipment_status;


