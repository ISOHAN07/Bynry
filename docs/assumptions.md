# 🚨 Low Stock Alert System — Business & Schema Assumptions

This document outlines all the **business rules**, **schema conventions**, and **assumptions** made to support a production-grade server that identifies low stock conditions across warehouses and generates supplier alerts.

---

## 1. 📦 Schema Conventions

- **`products`** table: `id`, `name`, `sku`, `type`, `low_stock_threshold`, `supplier_id`
- **`warehouses`** table: `id`, `name`, `company_id`
- **`product_stock`**: many-to-many join table with `product_id`, `warehouse_id`, `current_stock`
- **`sales`** table: `product_id`, `warehouse_id`, `quantity`, `sale_date` (timestamp)
- **`suppliers`**: `id`, `name`, `contact_email`

---

## 2. 🏢 Company ↔ Warehouse Relationship

- Every **warehouse** row includes a `company_id` that must match the query input.
- **Products** inherit `company_id` either directly or indirectly through warehouses in which they are stocked.

---

## 3. 📅 “Recent Sales” Window

- We define "recent" as **last 30 days**, configurable via a constant (`RECENT_SALES_DAYS`).
- Sales outside this window are **ignored** for velocity estimation.

---

## 4. 🚨 Threshold Logic

- Each product can define its own **`low_stock_threshold`**.
- If null, fallback logic is:
  - Use hardcoded thresholds per **`product_type`**
  - If unrecognized, use a **global default threshold**

---

## 5. 🧮 Stockout Estimation

- Average daily sales: `total_sold / RECENT_SALES_DAYS`
- If `avgDaily` = 0 → `days_until_stockout = null`
- Else → `days_until_stockout = ceil(current_stock / avgDaily)`

---

## 6. 🔎 Filtering Logic

- Only include `(product_id, warehouse_id)` pairs that:
  - Have had **recent sales** (`total_sold > 0`)
  - Have `current_stock < threshold`

---

## 7. 👨‍💼 Supplier Info

- Each product must have a `supplier_id` or be treated as having `supplier: null`
- No extra supplier metadata pulled other than: `id`, `name`, `contact_email`

---

## 8. 📃 Pagination

- Results are capped by a **`limit`** (default: 100)
- **`offset`** is supported to enable pagination

---

## 9. 🛡️ Error Handling & Validation

- If `companyId` is not a valid integer → **400 Bad Request**
- All unexpected internal errors → **500 Internal Server Error** with a generic response

---

## ✅ Summary

These rules provide a robust and extensible framework for managing real-time inventory alerting based on sales velocity, custom product thresholds, and multi-warehouse support. This ensures that the backend is consistent, scalable, and resilient for production use.

