-- ==============================================================================
-- 1. DATA CLEANING & TRANSFORMATION LAYER (VIEW CREATION)
-- ==============================================================================

CREATE OR REPLACE VIEW carsales.carsalesproject.view_final_cleaned_data AS

WITH ParsedSource AS (
    -- Parse dates immediately so chronological sorting works perfectly downstream
    SELECT *, 
        TO_DATE(CONCAT(selldate, ' ', _c16, ' ', _c17), 'MMM d yyyy') AS formatted_sale_date
    FROM `New_motor_carsales`.`motors_data`.`project_car_sales_dataset_new_coding`
),

Deduplicated AS (
    -- Remove duplicate VINs, sorting by the true parsed date
    SELECT *, 
           ROW_NUMBER() OVER (PARTITION BY vin ORDER BY formatted_sale_date DESC) as row_num
    FROM ParsedSource
    WHERE vin IS NOT NULL
),

Transformed AS (
    -- Enforce naming standards, data hygiene, and handle unknown values
    SELECT 
        year,
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
        formatted_sale_date,
        
        -- Standardize Makes
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
        END AS display_model
    FROM Deduplicated
    WHERE row_num = 1 -- Keep only the unique records
)

-- Final Select with calculated financial metrics
SELECT 
    *,
    -- Calculate Margin (Safeguarded against division by zero)
    ROUND(((sellingprice - mmr) / NULLIF(sellingprice, 0)) * 100, 2) AS profit_margin_percent,
    -- Margin Tiering
    CASE 
        WHEN ((sellingprice - mmr) / NULLIF(sellingprice, 0)) * 100 > 20 THEN 'High Margin (>20%)'
        ELSE 'Standard/Low Margin'
    END AS margin_category
FROM Transformed;


-- ==============================================================================
-- 2. REPORTING LAYER (EXECUTIVE DASHBOARD VIEW)
-- ==============================================================================

CREATE OR REPLACE VIEW carsales.carsalesproject.view_executive_dashboard AS
SELECT 
    -- Derived dimensions for time-intelligence filtering
    CONCAT('Q', EXTRACT(QUARTER FROM formatted_sale_date)) AS sale_quarter,
    DATE_FORMAT(formatted_sale_date, 'MMMM') AS sale_month_name,

    -- Core Dimensions
    formatted_sale_date,
    EXTRACT(YEAR FROM formatted_sale_date) AS sale_year, 
    CAST(year AS INT) AS vehicle_year,                 
    display_make,
    display_model,
    body,
    
    -- Financials
    sellingprice,
    mmr,
    profit_margin_percent,
    margin_category,
    
    -- Performance Drivers
    odometer,
    condition,
    color,
    COALESCE(NULLIF(state, ''), 'Unknown') AS display_state
FROM carsales.carsalesproject.view_final_cleaned_data;


-- ==============================================================================
-- 3. ANALYTICAL QUERIES FOR EXECUTIVE KPI VERIFICATION
-- ==============================================================================

-- KPI: Verification Preview (First 20 rows)
SELECT * FROM carsales.carsalesproject.view_final_cleaned_data LIMIT 20;

-- KPI: Total Corporate Revenue Volume
SELECT SUM(sellingprice) AS total_revenue
FROM carsales.carsalesproject.view_final_cleaned_data;

-- KPI: Distinct Entity Metrics (Fixes the row-count bug)
SELECT 
    COUNT(DISTINCT state) AS total_unique_states,
    COUNT(DISTINCT seller) AS total_unique_sellers
FROM carsales.carsalesproject.view_final_cleaned_data;

-- KPI: Revenue Contribution by Top 10 Models (Fixes the MAX/SUM bug)
SELECT 
    display_model, 
    SUM(sellingprice) AS total_model_revenue,
    ROUND((SUM(sellingprice) / SUM(SUM(sellingprice)) OVER()) * 100, 2) AS revenue_share_pct
FROM carsales.carsalesproject.view_final_cleaned_data
GROUP BY display_model
ORDER BY total_model_revenue DESC
LIMIT 10;

-- KPI: True Volume Share per Color (Fixes the non-deterministic random bug)
SELECT 
    COALESCE(NULLIF(color, ''), 'Unspecified') AS vehicle_color, 
    COUNT(*) AS units_sold,
    ROUND((COUNT(*) / SUM(COUNT(*)) OVER()) * 100, 2) AS market_share_pct
FROM carsales.carsalesproject.view_final_cleaned_data
GROUP BY color
ORDER BY units_sold DESC
LIMIT 5;

-- KPI: Profit Margin Categorization
SELECT 
    margin_category, 
    COUNT(*) AS total_transactions, 
    ROUND(AVG(profit_margin_percent), 2) AS avg_profit_margin_percent
FROM carsales.carsalesproject.view_final_cleaned_data
GROUP BY margin_category
ORDER BY total_transactions DESC;

-- KPI: Geographic Performance Ranking
SELECT 
    state, 
    COUNT(*) AS transactions_count,
    SUM(sellingprice) AS regional_revenue
FROM carsales.carsalesproject.view_final_cleaned_data
GROUP BY state
ORDER BY regional_revenue DESC
LIMIT 10;

-- KPI: Inventory Mileage Health Check
SELECT 
    display_make,
    ROUND(AVG(odometer), 0) AS avg_odometer_miles
FROM carsales.carsalesproject.view_final_cleaned_data
GROUP BY display_make
ORDER BY avg_odometer_miles DESC;

-- KPI: Recency Indexing (Days Since Transaction)
SELECT *,
       DATEDIFF(CURRENT_DATE(), formatted_sale_date) AS days_since_sale
FROM carsales.carsalesproject.view_final_cleaned_data
LIMIT 10;
