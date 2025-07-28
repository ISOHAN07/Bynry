-- 1. first we are going to design a table for the units of measure so as to get an standardized units
CREATE TABLE
    uom (
        uom_id SERIAL PRIMARY KEY,
        code TEXT NOT NULL UNIQUE, -- e.g. 'EA', 'KG', 'L'
        description TEXT
    );

-- 2. JSONB contact_info for flexible phone/email/address structures without extra tables.
-- created_at timestamp for auditing and record provenance.
-- SERIAL PK gives a simple unique identifier
CREATE TABLE
    company (
        company_id SERIAL PRIMARY KEY,
        name TEXT NOT NULL,
        address TEXT,
        contact_info JSONB, -- phone, email, etc.
        created_at TIMESTAMPTZ NOT NULL DEFAULT now ()
    );

-- 3. FK → company with ON DELETE CASCADE: deleting a company cleans up its warehouses automatically.
--     Index on company_id speeds lookups of all warehouses per company.
--     created_at for timeline and debugging
CREATE TABLE
    warehouse (
        warehouse_id SERIAL PRIMARY KEY,
        company_id INT NOT NULL REFERENCES company (company_id) ON DELETE CASCADE,
        name TEXT NOT NULL,
        address TEXT,
        created_at TIMESTAMPTZ NOT NULL DEFAULT now ()
    );

-- 4. Bin‑level granularity supports real‑world aisle/bin/shelf tracking.
-- UNIQUE(warehouse_id, code) prevents duplicate bin codes within one warehouse.
-- Cascade delete keeps bins in sync with parent warehouse.
CREATE TABLE
    warehouse_bin (
        bin_id SERIAL PRIMARY KEY,
        warehouse_id INT NOT NULL REFERENCES warehouse (warehouse_id) ON DELETE CASCADE,
        code TEXT NOT NULL,
        description TEXT,
        UNIQUE (warehouse_id, code)
    );

--5. Basic information regarding the supplier of the product
CREATE TABLE
    supplier (
        supplier_id SERIAL PRIMARY KEY,
        name TEXT NOT NULL,
        address TEXT,
        contact_info JSONB,
        payment_terms TEXT,
        created_at TIMESTAMPTZ NOT NULL DEFAULT now ()
    );

--6. Mirrors supplier for symmetry—needed if tracking sales orders.
-- sales_terms for credit/discount rules.
CREATE TABLE
    customer (
        customer_id SERIAL PRIMARY KEY,
        name TEXT NOT NULL,
        address TEXT,
        contact_info JSONB,
        sales_terms TEXT,
        created_at TIMESTAMPTZ NOT NULL DEFAULT now ()
    );

-- 7. sku UNIQUE enforces a single canonical code per product.
-- uom_id FK forces every product to pick a unit of measure.
-- Bundle flag drives bundle logic in application code.
-- Lot/Serial flags conditionally activate tracking tables.
-- Contains the basic details about the product and essential flags.
CREATE TABLE
    product (
        product_id SERIAL PRIMARY KEY,
        name TEXT NOT NULL,
        sku TEXT NOT NULL UNIQUE,
        description TEXT,
        uom_id INT NOT NULL REFERENCES uom (uom_id),
        is_bundle BOOLEAN NOT NULL DEFAULT FALSE,
        track_lots BOOLEAN NOT NULL DEFAULT FALSE,
        track_serials BOOLEAN NOT NULL DEFAULT FALSE,
        created_at TIMESTAMPTZ NOT NULL DEFAULT now ()
    );

-- 8. Self‑referencing FK lets any SKU be a bundle of other SKUs.
-- ON DELETE CASCADE on bundle ensures its components clear out if bundle deleted, but RESTRICT on components prevents orphaning references.
-- Composite PK prevents duplicate component entries.
CREATE TABLE
    product_bundle (
        bundle_id INT NOT NULL REFERENCES product (product_id) ON DELETE CASCADE,
        component_id INT NOT NULL REFERENCES product (product_id) ON DELETE RESTRICT,
        qty_per_bundle INT NOT NULL CHECK (qty_per_bundle > 0),
        PRIMARY KEY (bundle_id, component_id)
    );

-- 9.Per‑product batch tracking.
-- Unique constraint ensures each batch code is unique within that product.
-- Cascade when SKU is removed.
CREATE TABLE
    product_lot (
        lot_id SERIAL PRIMARY KEY,
        product_id INT NOT NULL REFERENCES product (product_id) ON DELETE CASCADE,
        lot_code TEXT NOT NULL,
        manufactured DATE,
        expires DATE,
        UNIQUE (product_id, lot_code)
    );

-- 10.For high‑value serialized items.
-- Global uniqueness on serial_code prevents duplicate tags
CREATE TABLE
    product_serial (
        serial_id SERIAL PRIMARY KEY,
        product_id INT NOT NULL REFERENCES product (product_id) ON DELETE CASCADE,
        serial_code TEXT NOT NULL UNIQUE
    );

-- 11.M‑N relationship capturing per‑supplier cost & lead time.
-- Composite PK avoids duplicate entries, FK cascades keep data clean.
CREATE TABLE
    product_supplier (
        product_id INT NOT NULL REFERENCES product (product_id) ON DELETE CASCADE,
        supplier_id INT NOT NULL REFERENCES supplier (supplier_id) ON DELETE CASCADE,
        unit_cost NUMERIC(12, 4),
        lead_time_days INT,
        PRIMARY KEY (product_id, supplier_id)
    );

-- * Important Note on Design Choice
-- By selectively enabling lot tracking, serial tracking, bundles, and the other features above only where they’re needed, we keep our system both flexible and performant. Each capability corresponds to a concrete operational or compliance requirement—together they give us full control over inventory, procurement, sales, and traceability.

-- 12. Tracks current on‑hand per exact location, lot, or serial.
-- Unique constraint prevents duplicate inventory rows for the same “slot”.
-- ON DELETE SET NULL for bin/lot/serial keeps the record but marks the sub‑location gone.
-- Check constraint enforces non‑negative stock.
CREATE TABLE inventory (
  inventory_id  SERIAL      PRIMARY KEY,
  warehouse_id  INT         NOT NULL REFERENCES warehouse(warehouse_id) ON DELETE CASCADE,
  bin_id        INT         REFERENCES warehouse_bin(bin_id) ON DELETE SET NULL,
  product_id    INT         NOT NULL REFERENCES product(product_id) ON DELETE RESTRICT,
  lot_id        INT         REFERENCES product_lot(lot_id) ON DELETE SET NULL,
  serial_id     INT         REFERENCES product_serial(serial_id) ON DELETE SET NULL,
  qty_on_hand   NUMERIC     NOT NULL CHECK (qty_on_hand >= 0),
  last_updated  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(warehouse_id, bin_id, product_id, lot_id, serial_id)
);

-- 13. Append‑only ledger: never overwrite history.
-- Indexes on txn_date & txn_type accelerate reporting and filtering by period or type.
-- change_qty signed allows both receipts (+) and issues (–).
CREATE TABLE inventory_transaction (
  txn_id        SERIAL      PRIMARY KEY,
  inventory_id  INT         NOT NULL REFERENCES inventory(inventory_id) ON DELETE CASCADE,
  change_qty    NUMERIC     NOT NULL,
  txn_type      TEXT        NOT NULL,
  reference_no  TEXT,
  txn_date      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_inv_txn_date ON inventory_transaction(txn_date);
CREATE INDEX idx_inv_txn_type ON inventory_transaction(txn_type);

-- 14. Per‑SKU, per‑warehouse reorder thresholds.
-- Checks ensure sane min/max relationships.
-- Drives automated PO generation
CREATE TABLE reorder_rule (
  product_id    INT         NOT NULL REFERENCES product(product_id) ON DELETE CASCADE,
  warehouse_id  INT         REFERENCES warehouse(warehouse_id) ON DELETE CASCADE,
  min_qty       NUMERIC     NOT NULL CHECK (min_qty >= 0),
  max_qty       NUMERIC     CHECK (max_qty >= min_qty),
  PRIMARY KEY (product_id, warehouse_id)
);

-- 15. Header + lines pattern captures complete PO information.
-- Status check enforces allowed states.
-- CASCADE on PO delete removes its lines cleanly.
CREATE TABLE purchase_order (
  po_id         SERIAL      PRIMARY KEY,
  company_id    INT         NOT NULL REFERENCES company(company_id) ON DELETE CASCADE,
  supplier_id   INT         REFERENCES supplier(supplier_id) ON DELETE SET NULL,
  order_date    DATE        NOT NULL,
  status        TEXT        NOT NULL CHECK (status IN ('OPEN','RECEIVED','CANCELLED')),
  total_amount  NUMERIC(14,2),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE purchase_order_line (
  po_line_id    SERIAL      PRIMARY KEY,
  po_id         INT         NOT NULL REFERENCES purchase_order(po_id) ON DELETE CASCADE,
  product_id    INT         NOT NULL REFERENCES product(product_id),
  uom_id        INT         NOT NULL REFERENCES uom(uom_id),
  qty_ordered   NUMERIC     NOT NULL CHECK (qty_ordered > 0),
  qty_received  NUMERIC     NOT NULL DEFAULT 0,
  unit_cost     NUMERIC(12,4) NOT NULL
);

-- 16. Mirrors PO structure for outbound flows.
-- qty_shipped lets you track partial shipments.
-- Same pattern of constraints for data integrity.
CREATE TABLE sales_order (
  so_id         SERIAL      PRIMARY KEY,
  company_id    INT         NOT NULL REFERENCES company(company_id) ON DELETE CASCADE,
  customer_id   INT         REFERENCES customer(customer_id) ON DELETE SET NULL,
  order_date    DATE        NOT NULL,
  status        TEXT        NOT NULL CHECK (status IN ('NEW','PICKED','SHIPPED','CANCELLED')),
  total_amount  NUMERIC(14,2),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE sales_order_line (
  so_line_id    SERIAL      PRIMARY KEY,
  so_id         INT         NOT NULL REFERENCES sales_order(so_id) ON DELETE CASCADE,
  product_id    INT         NOT NULL REFERENCES product(product_id),
  uom_id        INT         NOT NULL REFERENCES uom(uom_id),
  qty_ordered   NUMERIC     NOT NULL CHECK (qty_ordered > 0),
  qty_shipped   NUMERIC     NOT NULL DEFAULT 0,
  unit_price    NUMERIC(12,4) NOT NULL
);

-- 17. Time‑based pricing for sales or cost modeling.
-- No overlaps enforced here—you can add a constraint or trigger if you need it.
CREATE TABLE price_history (
  price_hist_id SERIAL      PRIMARY KEY,
  product_id    INT         NOT NULL REFERENCES product(product_id) ON DELETE CASCADE,
  valid_from    DATE        NOT NULL,
  valid_to      DATE,
  price         NUMERIC(12,4) NOT NULL,
  currency      TEXT        NOT NULL
);

-- 18. Centralized audit for INSERT/UPDATE/DELETE, storing changed_data as JSONB.
-- User foreign key ties events back to who made them.
CREATE TABLE app_user (
  user_id       SERIAL      PRIMARY KEY,
  username      TEXT        NOT NULL UNIQUE,
  full_name     TEXT,
  role          TEXT        NOT NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE audit_log (
  audit_id      SERIAL      PRIMARY KEY,
  table_name    TEXT        NOT NULL,
  record_id     INT         NOT NULL,
  operation     TEXT        NOT NULL,
  changed_data  JSONB,
  changed_by    INT         REFERENCES app_user(user_id) ON DELETE SET NULL,
  changed_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- * Important Note on the intution behind such a detailed schema 
-- The goal of this comprehensive schema is to mirror real‑world workflows—from procurement to picking to shipping—so we can enforce data integrity, trace every transaction, and adapt as requirements evolve. By modeling units of measure, lots, serials, bundles, reorder rules, and audit logs up front, we shift validation into the database, minimize future migrations, and ensure consistency. Normalizing core entities eliminates duplication while snapshot tables (like current inventory) deliver performant lookups. Feature flags and JSONB fields let us enable new capabilities on demand. In essence, this design balances rigor, flexibility, and scalability, anticipating both today’s needs and tomorrow’s growth.