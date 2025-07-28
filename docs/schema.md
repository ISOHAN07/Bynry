# 📦 Inventory Management System — Database Schema

Welcome! This repository outlines a comprehensive and extensible **Inventory, Procurement, and Sales** database schema designed for real-world warehouse and supply chain operations.

---

## 🔍 Overview

This schema supports:

- Multi-warehouse product storage with bin-level tracking
- Lot & serial number traceability
- Product bundles (kits) made of components
- Supplier and customer management
- Purchase and sales order workflows
- Reordering rules for restocking
- Audit logging and data integrity constraints

The design aims to balance **data normalization**, **performance**, and **future scalability**, making it suitable for ERP, WMS, e-commerce backends, or B2B distribution platforms.

---

## 🧱 Core Entities

| Entity             | Purpose                                                                 |
|--------------------|-------------------------------------------------------------------------|
| `company`          | Master table for organizations using the system                         |
| `warehouse`        | Physical storage locations per company                                  |
| `warehouse_bin`    | Bin/shelf/aisle-level location within a warehouse                       |
| `product`          | Master catalog of items, including flags for bundles, lots, serials     |
| `uom`              | Standardized units of measure (e.g., EA, KG, L)                         |
| `supplier`         | Vendors who supply products                                             |
| `customer`         | Buyers who receive goods                                                |
| `inventory`        | Tracks current stock by product, bin, lot, or serial                    |
| `inventory_transaction` | Ledger of stock movements (receipt, shipment, adjustment)          |
| `product_bundle`   | Defines the components that make up a bundled product                   |
| `product_lot`      | Optional lot/batch tracking for products                                |
| `product_serial`   | Optional serial tracking for unique items                               |
| `product_supplier` | Maps products to suppliers, costs, and lead times                       |
| `reorder_rule`     | Defines minimum/maximum stock thresholds for automatic restocking       |
| `purchase_order` & `purchase_order_line` | Manages inbound purchasing from suppliers         |
| `sales_order` & `sales_order_line`       | Manages outbound orders to customers              |
| `price_history`    | Historical prices per product and currency                              |
| `app_user`         | Application users (for auditing)                                        |
| `audit_log`        | Tracks changes to critical tables for compliance/debugging              |

---

## 🔄 Key Relationships

- A **company** owns multiple **warehouses**
- A **warehouse** has many **bins**
- A **product** may be a bundle (composed of other products)
- **Products** can be supplied by multiple **suppliers**
- **Inventory** is tracked per bin, product, lot, and/or serial
- **Inventory transactions** record every change in stock (receipt, sale, return, etc.)
- **Purchase orders** and **sales orders** flow through line items, driving inventory movements

---

## ⚙️ Advanced Features

### ✅ Lot and Serial Tracking
- Supports **perishable or regulated goods** (batches with expiry dates)
- Tracks high-value serialized items for warranty or compliance

### 📦 Bundles (Kits)
- Products can represent multi-SKU bundles
- Selling a bundle deducts the component items from inventory

### 🧮 Reorder Rules
- Automate reordering based on **min/max thresholds**
- Enables demand forecasting and procurement planning

### 📊 Price History
- Historical product pricing with optional multi-currency support
- Useful for auditing, analytics, and promotional tracking

### 🔐 Audit Logging
- Full **change tracking** with user attribution
- Records all inserts, updates, and deletes for critical tables

---

## 🎯 Use Case Scenarios

| Scenario                           | Tables Involved                                                 |
|------------------------------------|-----------------------------------------------------------------|
| Receiving stock from a supplier    | `purchase_order`, `inventory_transaction`, `inventory`          |
| Selling a product to a customer    | `sales_order`, `inventory_transaction`, `inventory`             |
| Creating a product bundle          | `product`, `product_bundle`                                     |
| Tracking a specific serial number  | `product_serial`, `inventory`, `inventory_transaction`          |
| Automatically restocking inventory | `reorder_rule`, `product_supplier`, `purchase_order`            |
| Performing stock adjustment        | `inventory_transaction`                                         |
| Viewing inventory by bin/location  | `inventory`, `warehouse_bin`, `warehouse`                       |

---

## 🧠 Design Philosophy

- **Normalization with performance**: Core data (products, warehouses, etc.) are normalized, but key snapshots (inventory state) are denormalized for fast querying.
- **Extensibility**: JSONB fields and modular tables allow for evolving requirements (e.g., contact details, extra metadata).
- **Auditability**: Most tables include `created_at`, and critical actions log to `audit_log`.
- **Flexibility**: You can run the schema with or without features like lots, serials, or bundles depending on business needs.