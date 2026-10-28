const express = require('express');
const router = express.Router();
const multer = require('multer');
const path = require('path');
const fs = require('fs');

const uploadDir = path.join(__dirname, '../../uploads');
if (!fs.existsSync(uploadDir)) fs.mkdirSync(uploadDir, { recursive: true });

const upload = multer({
  storage: multer.diskStorage({
    destination: (req, file, cb) => cb(null, uploadDir),
    filename: (req, file, cb) => cb(null, `${Date.now()}-${file.originalname}`),
  }),
});

const { authenticateApiToken, ensureAdmin } = require('../middleware/auth');

// Controllers
const health = require('../controllers/healthController');
const auth = require('../controllers/authController');
const settings = require('../controllers/settingsController');
const dashboard = require('../controllers/dashboardController');
const setup = require('../controllers/setupController');
const quotation = require('../controllers/quotationController');
const purchaseOrder = require('../controllers/purchaseOrderController');
const receiving = require('../controllers/receivingController');
const outslip = require('../controllers/outslipController');
const deliveryReceipt = require('../controllers/deliveryReceiptController');
const arContract = require('../controllers/arContractController');
const billing = require('../controllers/billingController');
const report = require('../controllers/reportController');
const accomplishment = require('../controllers/accomplishmentController');

// 1. Public Endpoints
router.get('/health', health.show);
router.post('/auth/login', auth.login);

// 2. Authenticated Endpoints
router.use(authenticateApiToken);

router.get('/auth/me', auth.me);
router.post('/auth/logout', auth.logout);

// Settings
router.get('/settings', settings.show);
router.put('/settings', ensureAdmin, settings.update);
router.put('/settings/password', settings.updatePassword);

// Dashboard
router.get('/dashboard/stats', dashboard.stats);

// Setup (Items barcode is public to users; setup CRUD is admin)
router.get('/setup/items/by-barcode/:barcode', setup.showItemByBarcode);
router.get('/setup/:resource', setup.index);
router.post('/setup/:resource', ensureAdmin, setup.store);
router.put('/setup/:resource/:id', ensureAdmin, setup.update);
router.delete('/setup/:resource/:id', ensureAdmin, setup.destroy);

// Quotations
router.get('/quotations', quotation.index);
router.post('/quotations', quotation.store);
router.put('/quotations/:id', quotation.update);
router.post('/quotations/:id/cancel', quotation.cancel);
router.post('/quotations/:id/convert-to-po', quotation.convertToPurchaseOrder);

// Purchase Orders
router.get('/purchase-orders', purchaseOrder.index);
router.delete('/purchase-orders/:id', ensureAdmin, purchaseOrder.destroy);
router.post('/purchase-orders/:id/receivings', purchaseOrder.createReceiving);

// Receivings
router.get('/receivings', receiving.index);
router.post('/receivings/:id/confirm', receiving.confirm);

// Outslips
router.get('/outslips', outslip.index);
router.get('/outslips/:id', outslip.show);
router.post('/outslips', outslip.store);
router.post('/outslips/:id/submit', outslip.submit);
router.post('/outslips/:id/approve', ensureAdmin, outslip.approve);
router.post('/outslips/:id/dispatch', ensureAdmin, outslip.dispatch);
router.get('/outslips/:id/gate-pass', outslip.showGatePass);
router.put('/outslips/:id/gate-pass', outslip.saveGatePass);
router.post('/outslips/:id/gate-pass/exit', outslip.markGatePassExit);
router.post('/outslips/:id/gate-pass/void', ensureAdmin, outslip.voidGatePass);

// Delivery Receipts
router.get('/delivery-receipts', deliveryReceipt.index);
router.get('/delivery-receipts/:id', deliveryReceipt.show);
router.post('/delivery-receipts', deliveryReceipt.store);
router.put('/delivery-receipts/:id/serials', deliveryReceipt.updateSerials);
router.post('/delivery-receipts/:id/status', deliveryReceipt.updateStatus);

// AR Contracts
router.get('/ar-contracts', arContract.index);
router.post('/ar-contracts', arContract.store);
router.get('/ar-contracts/:id', arContract.show);
router.put('/ar-contracts/:id', arContract.update);
router.delete('/ar-contracts/:id', arContract.destroy);
router.post('/ar-contracts/:id/recurring-lines', arContract.storeLine);
router.put('/ar-contracts/:id/recurring-lines/:lineId', arContract.updateLine);
router.delete('/ar-contracts/:id/recurring-lines/:lineId', arContract.destroyLine);

// Billings
router.get('/billings', billing.index);
router.post('/billings', billing.store);
router.post('/billings/:id/payments', billing.recordPayment);

// Reports
router.get('/reports/soa', report.soa);
router.get('/reports/customer-ledger', report.customerLedger);
router.get('/reports/supplier-ledger', report.supplierLedger);
router.get('/reports/inventory', report.inventory);

// Accomplishments
router.get('/accomplishments', accomplishment.index);
router.get('/accomplishments/:id', accomplishment.show);
router.post('/accomplishments', accomplishment.store);
router.put('/accomplishments/:id', accomplishment.update);
router.delete('/accomplishments/:id', accomplishment.destroy);
router.post('/accomplishments/:id/photos', upload.array('photos[]'), accomplishment.uploadPhotos);
router.delete('/accomplishments/:id/photos/:photoId', accomplishment.destroyPhoto);
router.get('/accomplishments/:id/photos/:photoId/file', accomplishment.showPhoto);

module.exports = router;