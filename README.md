# 📦 Inventory Management & Alerting System

This repository provides a robust, production-grade inventory tracking and alerting system. It includes schema design, backend code, and detailed documentation for handling low-stock notifications, product creation, warehouse integration, and supplier coordination.

---

## 📁 Project Structure

```
.
├── docs/
│   ├── assumptions.md        # Business rules and data assumptions which required for the Part 3 of the assignment 
│   ├── review_issue.md       # API flaws and technical review feedback obtained from the Part 1 of the assignment 
│   └── schema.md             # Detailed database schema explanation for the Part 2 of the assignment 
│
├── src/
│   ├── Part 1/
│   │   └── fixed_code.py     # Secure & validated product + inventory API
│   ├── Part 2/
│   │   └── schema.sql        # Complete relational schema with constraints
│   └── Part 3/
│       └── server.js         # Low-stock alert server logic
```

---

## 🚀 Features

- 🔒 Secure product creation with validation and rollback
- 🏭 Multi-warehouse inventory tracking
- ⏱ Stockout prediction based on sales velocity
- 📉 Low-stock alerting based on dynamic thresholds
- 📬 Supplier linking for reorder workflows
- ✅ Well-documented schema & assumptions

---

## 📚 Key Documentation

- [docs/assumptions.md](docs/assumptions.md): Low-stock logic, thresholds, filtering, and supplier rules.
- [docs/review_issue.md](docs/review_issue.md): Analysis of flaws in the original codebase.
- [docs/schema.md](docs/schema.md): In-depth ERD with justifications for every design decision.

---

## 🔧 Technologies Used

- PostgreSQL (schema & inventory logic)
- Python (validation & secure API)
- Node.js (alerting service)
- SQL + ER principles

---

## 🧠 Why This Matters

This project showcases proper system design across API layers, databases, and alerting logic—all backed by clear documentation and industry best practices.
