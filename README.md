# ERP System (RTS Mobile)

Mobile field app and REST API for **ResponsivCode / RTS** ERP workflows. The Flutter client talks to a decoupled **Node.js** backend over JSON; data lives in **MySQL** (same schema as the office ERP).

**Repository:** [github.com/ElgieYtang/ERP_System_RTS-Mobile](https://github.com/ElgieYtang/ERP_System_RTS-Mobile)

## Features

### Mobile app (`erp-client`)
- Login with API token auth; configurable server URL (saved on device)
- Dashboard with transaction shortcuts
- **Transactions:** Quotations, Purchase Orders, Receiving, Outslips, Delivery Receipts, Billing, Statement of Account (SOA)
- **Accomplishments:** field reports with photos
- Barcode scanning (items / delivery workflows)
- PDF generation and printing for documents
- Android-focused build (see `pubspec.yaml`)

### API (`erp-server`)
- Express REST API mounted at **`/api/mobile`**
- JWT / API token middleware
- Modules aligned with mobile: quotations, POs, receiving, outslips, gate pass, delivery receipts, AR contracts, billing, reports, accomplishments
- Health check: `GET /api/mobile/health`
- Expects an existing **MySQL ERP schema** (Laravel/WAMP-style tables); server validates table names on startup

## Tech stack

| Layer | Stack |
|--------|--------|
| **Mobile** | Flutter 3.3+, Provider, `http`, SharedPreferences, image_picker, mobile_scanner, pdf / printing |
| **Backend** | Node.js, Express 5, Sequelize, mysql2, JWT, bcrypt, multer |
| **Database** | MySQL (`rts_system` by default) |

## Project structure
