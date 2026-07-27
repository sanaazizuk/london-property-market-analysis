CREATE DATABASE london_house_prices;
USE london_house_prices;
SELECT * FROM fact_house_prices LIMIT 5;
SELECT COUNT(*) FROM fact_house_prices;

#median price per borough per year
SELECT 
    borough,
    YEAR(sale_date) AS sale_year,
    AVG(price) AS avg_price,
    COUNT(*) AS num_sales
FROM fact_house_prices
GROUP BY borough, YEAR(sale_date)
ORDER BY borough, sale_year;

#lets calculate median price instead of average
SELECT borough, sale_year, price,
       PERCENT_RANK() OVER (PARTITION BY borough, sale_year ORDER BY price) AS pct_rank
FROM (
    SELECT borough, YEAR(sale_date) AS sale_year, price
    FROM fact_house_prices
) AS sub

#wrap this in an outer query to actually pull out the median price
SELECT borough, sale_year, price AS median_price
FROM (
    SELECT borough, sale_year, price,
           PERCENT_RANK() OVER (PARTITION BY borough, sale_year ORDER BY price) AS pct_rank
    FROM (
        SELECT borough, YEAR(sale_date) AS sale_year, price
        FROM fact_house_prices
    ) AS sub
) AS ranked
WHERE pct_rank BETWEEN 0.49 AND 0.51
ORDER BY borough, sale_year;

#tidy this into one single median value per borough per year
SELECT borough, sale_year, ROUND(AVG(price)) AS median_price
FROM (
    SELECT borough, sale_year, price,
           PERCENT_RANK() OVER (PARTITION BY borough, sale_year ORDER BY price) AS pct_rank
    FROM (
        SELECT borough, YEAR(sale_date) AS sale_year, price
        FROM fact_house_prices
    ) AS sub
) AS ranked
WHERE pct_rank BETWEEN 0.49 AND 0.51
GROUP BY borough, sale_year
ORDER BY borough, sale_year;
#One thing worth noticing straight away: 2017, 2020, and 2024 are missing for Barking and Dagenham in what's visible here (it jumps 2016 → 2018 → 2019 → 2021 → 2022...)
#quickly check if this is a real gap or just this specific query missing some years
SELECT borough, sale_year, COUNT(*) AS num_sales
FROM (
    SELECT borough, YEAR(sale_date) AS sale_year, price
    FROM fact_house_prices
) AS sub
WHERE borough = 'BARKING AND DAGENHAM'
GROUP BY borough, sale_year
ORDER BY sale_year;
#so the missing years weren't a real data gap, just the 0.49–0.51 window

# to fix widen the percent_rank window slightly
SELECT borough, sale_year, ROUND(AVG(price)) AS median_price
FROM (
    SELECT borough, sale_year, price,
           PERCENT_RANK() OVER (PARTITION BY borough, sale_year ORDER BY price) AS pct_rank
    FROM (
        SELECT borough, YEAR(sale_date) AS sale_year, price
        FROM fact_house_prices
    ) AS sub
) AS ranked
WHERE pct_rank BETWEEN 0.48 AND 0.52
GROUP BY borough, sale_year
ORDER BY borough, sale_year;

#Save the median price query as a view
CREATE VIEW vw_median_price_by_borough_year AS
SELECT borough, sale_year, ROUND(AVG(price)) AS median_price
FROM (
    SELECT borough, sale_year, price,
           PERCENT_RANK() OVER (PARTITION BY borough, sale_year ORDER BY price) AS pct_rank
    FROM (
        SELECT borough, YEAR(sale_date) AS sale_year, price
        FROM fact_house_prices
    ) AS sub
) AS ranked
WHERE pct_rank BETWEEN 0.48 AND 0.52
GROUP BY borough, sale_year;

SELECT * FROM vw_median_price_by_borough_year ORDER BY borough, sale_year;

#year-over-year growth
SELECT 
    borough,
    sale_year,
    median_price,
    LAG(median_price) OVER (PARTITION BY borough ORDER BY sale_year) AS prev_year_price,
    ROUND(
        (median_price - LAG(median_price) OVER (PARTITION BY borough ORDER BY sale_year)) 
        / LAG(median_price) OVER (PARTITION BY borough ORDER BY sale_year) * 100
    , 2) AS yoy_growth_pct
FROM vw_median_price_by_borough_year
ORDER BY borough, sale_year;

#save this as a view too
CREATE VIEW vw_yoy_growth_by_borough AS
SELECT 
    borough,
    sale_year,
    median_price,
    LAG(median_price) OVER (PARTITION BY borough ORDER BY sale_year) AS prev_year_price,
    ROUND(
        (median_price - LAG(median_price) OVER (PARTITION BY borough ORDER BY sale_year)) 
        / LAG(median_price) OVER (PARTITION BY borough ORDER BY sale_year) * 100
    , 2) AS yoy_growth_pct
FROM vw_median_price_by_borough_year;

SELECT * FROM vw_yoy_growth_by_borough ORDER BY borough, sale_year LIMIT 20;

#Rank boroughs by their overall growth from 2016 to 2026
SELECT 
    borough,
    MIN(sale_year) AS start_year,
    MAX(sale_year) AS end_year,
    MIN(CASE WHEN sale_year = 2016 THEN median_price END) AS price_2016,
    MAX(CASE WHEN sale_year = 2026 THEN median_price END) AS price_2026
FROM vw_median_price_by_borough_year
GROUP BY borough
ORDER BY borough;

#calculate the actual growth percentage and rank all 33 boroughs
SELECT 
    borough,
    price_2016,
    price_2025,
    ROUND((price_2025 - price_2016) / price_2016 * 100, 2) AS growth_pct,
    RANK() OVER (ORDER BY (price_2025 - price_2016) / price_2016 DESC) AS growth_rank
FROM (
    SELECT 
        borough,
        MIN(CASE WHEN sale_year = 2016 THEN median_price END) AS price_2016,
        MAX(CASE WHEN sale_year = 2025 THEN median_price END) AS price_2025
    FROM vw_median_price_by_borough_year
    GROUP BY borough
) AS yearly;

#Save this as a view too

CREATE VIEW vw_borough_growth_ranking AS
SELECT 
    borough,
    price_2016,
    price_2025,
    ROUND((price_2025 - price_2016) / price_2016 * 100, 2) AS growth_pct,
    RANK() OVER (ORDER BY (price_2025 - price_2016) / price_2016 DESC) AS growth_rank
FROM (
    SELECT 
        borough,
        MIN(CASE WHEN sale_year = 2016 THEN median_price END) AS price_2016,
        MIN(CASE WHEN sale_year = 2025 THEN median_price END) AS price_2025
    FROM vw_median_price_by_borough_year
    GROUP BY borough
) AS yearly;

SELECT * FROM vw_borough_growth_ranking ORDER BY growth_rank;

#Check transaction counts for these two boroughs, year by year, to see if 2026 (or any other year) is suspiciously thin
SELECT borough, YEAR(sale_date) AS sale_year, COUNT(*) AS num_sales
FROM fact_house_prices
WHERE borough IN ('CITY OF LONDON', 'HAMMERSMITH AND FULHAM')
GROUP BY borough, YEAR(sale_date)
ORDER BY borough, sale_year;

#Key Findings , SQL Analysis (London House Prices)

#1. A median price per borough per year was calculated using PERCENT_RANK, since MySQL has no built in median function. Values were cross checked against simple averages and matched closely,
#confirming the cleaning done earlier in Python was effective and no major outliers remained.

#2. Year over year growth was calculated for every borough using LAG, showing that price movements are not steady year to year even within the same borough. 
#Barking and Dagenham, for example, saw a 10.69 percent jump in 2022 followed by a 3.33 percent dip in 2024, showing that yearly volatility exists even within a longer term upward trend.

#3. A ten year growth ranking (2016 to 2025) was built comparing each borough's starting and ending median price, 
#using 2025 as the final complete year rather than 2026, since 2026 is only a partial year and was found to distort the comparison. 
#Outer London boroughs dominate the top of the list, led by Havering at 35.88 percent, Bexley at 31.35 percent, and Sutton at 31.30 percent. 
#This matches a known real pattern in London property, where cheaper outer boroughs often show faster percentage growth than already expensive central ones.

#4. Four boroughs, City of Westminster, Kensington and Chelsea, City of London, and Hammersmith and Fulham, showed genuine price decreases over this period rather than growth, 
#ranging from minus 4.68 percent to minus 15.35 percent. Unlike the earlier apparent decline in City of London and Hammersmith and Fulham, 
#which was originally caused by the 2026 partial year distortion, these four declines held up after recalculating with 2025 as the endpoint, 
#and are consistent with known real pressures on prime central London values over this period, including higher stamp duty on expensive properties, 
#reduced international buyer activity, and a shift in demand toward outer boroughs.

#5. Three reusable SQL views were created to support the Tableau dashboard: vw_median_price_by_borough_year, vw_yoy_growth_by_borough, 
#and vw_borough_growth_ranking. These give Tableau clean, pre aggregated tables to connect to directly rather than working from over a million raw transaction rows. 
#Views were exported to CSV for the Tableau Public dashboard, since Tableau Public (free version) does not support live database connections, unlike Tableau Desktop.

SELECT * FROM vw_median_price_by_borough_year;
SELECT * FROM vw_yoy_growth_by_borough;
SELECT * FROM vw_borough_growth_ranking;


SELECT borough, price_2016, price_2025
FROM (
    SELECT borough,
        MIN(CASE WHEN sale_year = 2016 THEN median_price END) AS price_2016,
        MIN(CASE WHEN sale_year = 2025 THEN median_price END) AS price_2025
    FROM vw_median_price_by_borough_year
    GROUP BY borough
) AS yearly
WHERE borough IN ('KENSINGTON AND CHELSEA', 'CITY OF WESTMINSTER', 'CAMDEN', 'HAMMERSMITH AND FULHAM', 'CITY OF LONDON');

#borough grid
SELECT 
    borough,
    growth_pct,
    growth_rank,
    (growth_rank - 1) % 6 AS grid_col,
    FLOOR((growth_rank - 1) / 6) AS grid_row
FROM vw_borough_growth_ranking
ORDER BY growth_rank;


SELECT 
    property_type,
    new_build,
    COUNT(*) AS num_sales,
    ROUND(AVG(price)) AS avg_price
FROM fact_house_prices
WHERE YEAR(sale_date) = 2025
GROUP BY property_type, new_build
ORDER BY property_type, new_build;

SELECT new_build, ROUND(AVG(price)) AS avg_price
FROM fact_house_prices
WHERE property_type = 'F'
  AND YEAR(sale_date) = 2025
GROUP BY new_build;