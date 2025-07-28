1. Schema Conventions
    1. products table has columns id, name, sku, type, low_stock_threshold, and supplier_id.
    2. warehouses table has columns id, name, and company_id.
    3. product_stock table joins product_id ↔ warehouse_id with a column current_stock.
    4. sales table records each sale with product_id, warehouse_id, quantity, and a timestamp sale_date.
    5. suppliers table has at least id, name, and contact_email.

2. Company ↔ Warehouse Relationship
    1. Every warehouse row includes a company_id that matches the company we’re querying.
    2. Products inherit their company_id either directly or indirectly via the warehouses they’re stocked in.

3. “Recent Sales” Window
    1. We define “recent” as the last 30 days (configurable via RECENT_SALES_DAYS)
    2. Sales older than that window are ignored when determining stock velocity.

4. Threshold Logic
    1. A product can carry its own low_stock_threshold override; if that’s NULL, we fall back to a hard‑coded default based on product_type.
    2. If a product_type isn’t recognized, we use a global default threshold.

5. Stockout Estimation
    1. We compute average daily sales as (total_sold ÷ RECENT_SALES_DAYS).
    2. If that average is zero, days_until_stockout is set to null; otherwise we ceil(current_stock ÷ avgDaily).

6. Filtering
    1. Only include product+warehouse combinations that have any recent sales (i.e. total_sold > 0).
    2. Only include those whose current_stock < threshold.

7. Suppliers
    1. We assume every product either has a valid supplier_id or none—if none exists, we return supplier: null.
    2. No additional supplier metadata beyond id, name, and contact_email is pulled.

8. Pagination
    1. We cap results with limit (default 100) and support offset to avoid overwhelming clients or the database.

9. Error Handling & Validation
    1. We validate that companyId is a valid integer and return a 400 if not.
    2. Any unexpected error returns a 500 with a generic message.

These are all the assumptions made for the database and the business logic based on which a production grade server for alerting the low stock count is created. 
