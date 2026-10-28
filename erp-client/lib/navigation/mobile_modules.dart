import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../screens/accomplishments_page.dart';
import '../screens/billing_page.dart';
import '../screens/deliveries_page.dart';
import '../screens/outslips_page.dart';
import '../screens/purchase_orders_page.dart';
import '../screens/quotations_page.dart';
import '../screens/receivings_page.dart';
import '../screens/soa_page.dart';

/// Matches the web sidebar **TRANSACTIONS** section only (not Setup or Reports).
enum MobileModule {
  home,
  quotations,
  purchaseOrders,
  receiving,
  outslips,
  deliveries,
  billing,
  soa,
  accomplishments,
}

class MobileModuleInfo {
  const MobileModuleInfo({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gridLabel,
  });

  final MobileModule id;
  final String title;
  final String subtitle;
  final IconData icon;
  /// Short label under the dashboard icon grid.
  final String gridLabel;
}

const mobileModules = <MobileModuleInfo>[
  MobileModuleInfo(
    id: MobileModule.quotations,
    title: 'Quotations',
    subtitle: 'Approve and convert to PO',
    icon: Icons.request_quote_outlined,
    gridLabel: 'Quotations',
  ),
  MobileModuleInfo(
    id: MobileModule.purchaseOrders,
    title: 'Purchase Orders',
    subtitle: 'Receive items from suppliers',
    icon: Icons.shopping_cart_outlined,
    gridLabel: 'PO',
  ),
  MobileModuleInfo(
    id: MobileModule.receiving,
    title: 'Receiving',
    subtitle: 'Confirm warehouse intake',
    icon: Icons.inventory_2_outlined,
    gridLabel: 'Receive',
  ),
  MobileModuleInfo(
    id: MobileModule.outslips,
    title: 'Outslips',
    subtitle: 'Approve and dispatch stock',
    icon: Icons.outbox_outlined,
    gridLabel: 'Outslip',
  ),
  MobileModuleInfo(
    id: MobileModule.deliveries,
    title: 'Delivery Receipts',
    subtitle: 'Track delivery status',
    icon: Icons.local_shipping_outlined,
    gridLabel: 'Delivery',
  ),
  MobileModuleInfo(
    id: MobileModule.billing,
    title: 'Billing',
    subtitle: 'Record customer payments',
    icon: Icons.receipt_long_outlined,
    gridLabel: 'Billing',
  ),
  MobileModuleInfo(
    id: MobileModule.soa,
    title: 'Statement of Account',
    subtitle: 'Customer balances',
    icon: Icons.account_balance_wallet_outlined,
    gridLabel: 'SOA',
  ),
  MobileModuleInfo(
    id: MobileModule.accomplishments,
    title: 'Accomplishments',
    subtitle: 'Field photo reports',
    icon: Icons.photo_camera_outlined,
    gridLabel: 'Reports',
  ),
];

Widget buildMobileModulePage(MobileModule module, ApiClient api) {
  switch (module) {
    case MobileModule.home:
      throw ArgumentError('Home is not a module page');
    case MobileModule.quotations:
      return QuotationsPage(api: api);
    case MobileModule.purchaseOrders:
      return PurchaseOrdersPage(api: api);
    case MobileModule.receiving:
      return ReceivingsPage(api: api);
    case MobileModule.outslips:
      return OutslipsPage(api: api);
    case MobileModule.deliveries:
      return DeliveriesPage(api: api);
    case MobileModule.billing:
      return BillingPage(api: api);
    case MobileModule.soa:
      return SoaPage(api: api);
    case MobileModule.accomplishments:
      return AccomplishmentsPage(api: api);
  }
}

String mobileModuleTitle(MobileModule module) {
  return mobileModules.firstWhere((item) => item.id == module).title;
}
