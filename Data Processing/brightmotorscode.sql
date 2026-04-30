---Viewing table
SELECT*
FROM new_motor_carsales.motors_data.project_car_sales_dataset_new_coding;

---Combing date
SELECT 
  *,
  -- Combine into a string 'Dec 16 2014' and convert to Date
  TO_DATE(CONCAT(selldate, ' ', _c16, ' ', _c17), 'MMM d yyyy') AS formatted_sale_date
FROM `New_motor_carsales`.`motors_data`.`project_car_sales_dataset_new_coding`;

SELECT 
  year,
  make,
  model,
  sellingprice,
  mmr,
  condition,
  odometer,
  formatted_sale_date,
  trim,
  body,
  transmission,
  vin,
  state,
  interior,
  seller,
  color,
  selltime
FROM (
  SELECT 
    *,
    TO_DATE(CONCAT(selldate, ' ', _c16, ' ', _c17), 'MMM d yyyy') AS formatted_sale_date
  FROM `New_motor_carsales`.`motors_data`.`project_car_sales_dataset_new_coding`
) AS subquery;



-- 1. Create a "Cleaned" version of your data as a View
CREATE OR REPLACE VIEW carsales.carsalesproject.view_final_cleaned_data AS

WITH Deduplicated AS (
    -- Remove duplicate VINs, keeping the most recent sale
    SELECT *, 
           ROW_NUMBER() OVER (PARTITION BY vin ORDER BY selldate DESC) as row_num
    FROM `New_motor_carsales`.`motors_data`.`project_car_sales_dataset_new_coding`
    WHERE vin IS NOT NULL
),
Transformed AS (
    SELECT 
        year,
        make,
        model,
        sellingprice,
        mmr,
        condition,
        odometer,
        body,
        color,
        trim,
        transmission,
        vin,
        state,
        interior,
        seller,
        selltime,
        
        -- Standardize Makes (e.g., ford/ford truck -> Ford)
        CASE 
            WHEN LOWER(make) LIKE '%ford%' THEN 'Ford'
            WHEN LOWER(make) LIKE '%chev%' THEN 'Chevrolet'
            WHEN LOWER(make) LIKE '%nissan%' THEN 'Nissan'
            WHEN make = 'Unknown' OR make IS NULL THEN 'Unspecified'
            ELSE make 
        END AS display_make,
        
        -- Standardize Models (Remove numeric noise)
        CASE 
            WHEN model REGEXP '^[0-9]+$' THEN 'Unspecified'
            WHEN model = 'Unknown' OR model IS NULL THEN 'Unspecified'
            ELSE model 
        END AS display_model,
        
        -- Unified Date conversion (Assuming columns are selldate, _c16, _c17)
        TO_DATE(CONCAT(selldate, ' ', _c16, ' ', _c17), 'MMM d yyyy') AS formatted_sale_date
        
    FROM Deduplicated
    WHERE row_num = 1 -- Keep only the unique records
)
-- Final Select with business metrics
SELECT 
    *,
    -- Calculate Margin
    ROUND(((sellingprice - mmr) / NULLIF(sellingprice, 0)) * 100, 2) AS profit_margin_percent,
    -- Margin Tiering
    CASE 
        WHEN ((sellingprice - mmr) / NULLIF(sellingprice, 0)) * 100 > 20 THEN 'High Margin (>20%)'
        ELSE 'Standard/Low Margin'
    END AS margin_category
FROM Transformed;


SELECT * FROM carsales.carsalesproject.view_final_cleaned_data LIMIT 20;


---Total Revenue   (7485971110)
SELECT SUM(sellingprice) AS total_revenue
FROM carsales.carsalesproject.view_final_cleaned_data;


---Number of make
SELECT DISTINCT display_make 
FROM carsales.carsalesproject.view_final_cleaned_data
LIMIT30;


---Profit margin
SELECT margin_category, COUNT(*) AS count, ROUND(AVG(profit_margin_percent),2) AS avg_profit_margin_percent
FROM carsales.carsalesproject.view_final_cleaned_data
GROUP BY margin_category
ORDER BY count DESC;


---Number of state (550297)
SELECT COUNT(state)  AS total_state
FROM carsales.carsalesproject.view_final_cleaned_data
LIMIT30;


---Number of sellers(550297)
SELECT COUNT(seller) AS total_sellers
FROM carsales.carsalesproject.view_final_cleaned_data;


---Most expensive model
SELECT MAX(sellingprice) AS max_price, display_model
      FROM carsales.carsalesproject.view_final_cleaned_data
GROUP BY display_model
ORDER BY max_price DESC
LIMIT 11;

---Top 10 performing states
SELECT state, COUNT(*) AS count
FROM carsales.carsalesproject.view_final_cleaned_data
GROUP BY state
ORDER BY count DESC
LIMIT 10;

---Average make
SELECT AVG(odometer) AS avg_odometer, display_make
FROM carsales.carsalesproject.view_final_cleaned_data
GROUP BY display_make
LIMIT 5;

---Popular color
SELECT DISTINCT(color) AS popular_color
FROM carsales.carsalesproject.view_final_cleaned_data
GROUP BY color
LIMIT 5;



---Most profitable model
SELECT MAX(profit_margin_percent) AS max_profit_margin_percent, display_model
FROM carsales.carsalesproject.view_final_cleaned_data
GROUP BY display_model
LIMIT 15;



---Creating columns for the number of days between the sale date and the current date
SELECT *,
       DATEDIFF(CURRENT_DATE(), formatted_sale_date) AS days_since_sale
FROM carsales.carsalesproject.view_final_cleaned_data
LIMIT 10;


---Creating a view for the executive dashboard
CREATE OR REPLACE VIEW carsales.carsalesproject.view_executive_dashboard AS
SELECT 
-- Derived dimensions (Add these if you want specific labels for tables)
    CONCAT('Q', EXTRACT(QUARTER FROM formatted_sale_date)) AS sale_quarter,
    DATE_FORMAT(formatted_sale_date, 'MMMM') AS sale_month_name,

    -- Dimensions
    formatted_sale_date,
    EXTRACT(YEAR FROM formatted_sale_date) AS sale_year, -- Use this for yearly trends
    CAST(year AS INT) AS vehicle_year,                 -- The year the car was made
    display_make,
    display_model,
    body,
    -- Financials
    sellingprice,
    mmr,
    profit_margin_percent,
    margin_category,
    -- Drivers
    odometer,
    condition,
    color,
    COALESCE(NULLIF(state, ''), 'Unknown') AS display_state
FROM carsales.carsalesproject.view_final_cleaned_data;


SELECT * FROM carsales.carsalesproject.view_executive_dashboard LIMIT 10;


---Adding Insights for analysis
SELECT
-- Dimensions
    formatted_sale_date,
    EXTRACT(YEAR FROM formatted_sale_date) AS sale_year, -- for yearly trends
    CAST(vehicle_year AS INT) AS vehicle_year,                 -- The year the car was made
    display_make,
    display_model,
    body,
    -- Financials
    sellingprice,
    mmr,
    profit_margin_percent,
    margin_category,
    -- Drivers
    odometer,
    condition,
    color,
    sale_quarter,
    sale_month_name,
     display_state
    FROM carsales.carsalesproject.view_executive_dashboard;


