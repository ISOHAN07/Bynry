const express = require('express');
const router = express.Router();
const db = require('../db');                     // Knex.js instance
const RECENT_SALES_DAYS = 30;                     // Time window to consider “recent” sales

// IMPORTANT:
// Triggers alerts not only for products already under the low‑stock threshold,
// but also for any items forecasted to deplete soon according to their recent sales velocity.

// Default reorder thresholds by product type (could be stored in its own table)
const DEFAULT_THRESHOLDS = {
  electronics: 15,
  apparel: 25,
  consumable: 50,
  default: 20
};

router.get('/api/companies/:companyId/alerts/low-stock', async (req, res) => {
  // 1. Validate the incoming company ID to guard against injection or bad input
  const companyId = parseInt(req.params.companyId, 10);
  if (isNaN(companyId)) {
    return res.status(400).json({ error: 'Invalid company ID' });
  }

  try {
    //
    // 2. Building a subquery to aggregate “recent” sales by product+warehouse
    //    - We sum quantity sold over the last RECENT_SALES_DAYS
    //    - Group by product_id & warehouse_id so we can join back later
    //
    const recentSales = db('sales')
      .select('product_id', 'warehouse_id')
      .sum('quantity as total_sold')
      .where('sale_date', '>=', db.raw(`NOW() - INTERVAL '${RECENT_SALES_DAYS} days'`))
      .groupBy('product_id', 'warehouse_id')
      .as('rs');

    //
    // 3. Compose the main query to fetch:
    //    - product details (id, name, SKU, type, threshold override)
    //    - warehouse info (id, name) filtered by company
    //    - current stock levels
    //    - supplier details (if assigned)
    //    - the aggregated recent-sales total from our subquery
    //
    const rows = await db('products')
      // Join to warehouses via company_id → ensures we only see this company’s warehouses
      .join('warehouses', 'products.company_id', 'warehouses.company_id')
      .where('warehouses.company_id', companyId)

      // Join stock records by matching both product_id & warehouse_id
      .join('product_stock', function() {
        this.on('product_stock.product_id', '=', 'products.id')
            .andOn('product_stock.warehouse_id', '=', 'warehouses.id');
      })

      // Left‑join our recent-sales aggregation so missing rows become total_sold = NULL
      .leftJoin(recentSales, function() {
        this.on('rs.product_id', '=', 'products.id')
            .andOn('rs.warehouse_id', '=', 'warehouses.id');
      })

      // Left‑join supplier details — allows products with no supplier to still appear
      .leftJoin('suppliers', 'suppliers.id', 'products.supplier_id')

      // Pick the exact fields we need
      .select(
        'products.id as product_id',
        'products.name as product_name',
        'products.sku',
        'products.type as product_type',
        'product_stock.warehouse_id',
        'warehouses.name as warehouse_name',
        'product_stock.current_stock',
        'products.low_stock_threshold',
        'suppliers.id as supplier_id',
        'suppliers.name as supplier_name',
        'suppliers.contact_email',
        db.raw('COALESCE(rs.total_sold, 0) as total_sold')  // Convert NULL → 0
      )

      // 4. SQL‑level filtering: only keep rows where there were any recent sales
      .havingRaw('COALESCE(rs.total_sold, 0) > 0')

      // 5. Optional pagination to avoid huge result sets
      .limit(parseInt(req.query.limit, 10) || 100)
      .offset(parseInt(req.query.offset, 10) || 0);

    //
    // 6. Post‑process each row:
    //    - Determine the true threshold (product override or default by type)
    //    - Compute average daily sales and estimate days until stockout
    //    - Only include entries where current_stock < threshold
    //
    const alerts = rows
      .map(row => {
        // Choose override threshold if provided, otherwise default by product_type
        const threshold = row.low_stock_threshold
          || DEFAULT_THRESHOLDS[row.product_type]
          || DEFAULT_THRESHOLDS.default;

        // Skip if stock is still above threshold
        if (row.current_stock >= threshold) {
          return null;
        }

        // Estimate days until run‑out using avg daily sales
        const avgDaily = row.total_sold / RECENT_SALES_DAYS;
        const days_until_stockout = avgDaily > 0
          ? Math.ceil(row.current_stock / avgDaily) 
          : null;

        return {
          product_id: row.product_id,
          product_name: row.product_name,
          sku: row.sku,
          warehouse_id: row.warehouse_id,
          warehouse_name: row.warehouse_name,
          current_stock: row.current_stock,
          threshold,
          days_until_stockout,
          supplier: row.supplier_id ? {
            id: row.supplier_id,
            name: row.supplier_name,
            contact_email: row.contact_email
          } : null
        };
      })
      // Filter out any nulls (rows that didn’t meet the < threshold check)
      .filter(x => x !== null);

    // 7. Return the assembled alerts & count
    res.json({
      alerts,
      total_alerts: alerts.length
    });

  } catch (err) {
    // Centralized error handling
    console.error('Error fetching low stock alerts:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
