# 💳 How to Set Up Top-Up / In-App Payments in Baatkry

This guide explains how to set up payment top-ups in Baatkry so users can buy coin packages to unlock gender-filtered chat.

---

## 1. Overview of Mobile vs Web Payment Rules

* **For Google Play & Apple App Store (Android & iOS):**
  * App store guidelines **strictly require** using official **Google Play Billing** and **Apple In-App Purchase (IAP)** when selling virtual currency (coins) that are consumed inside the app.
* **For Web & Direct APK (Pakistan & International):**
  * You can integrate Pakistani local payment gateways (**JazzCash, Easypaisa, Safepay, PayFast, Kuickpay**) or international cards (**Stripe, Lemonsqueezy**).

---

## 2. Option A: Mobile App Store Top-Up (Google Play & Apple IAP)

This is the standard and compliant method for Play Store and App Store release.

### Step 1: Add the Official Flutter IAP Dependency
In `pubspec.yaml`:
```yaml
dependencies:
  in_app_purchase: ^3.2.0
```
Run `flutter pub get`.

### Step 2: Create In-App Products in Console
Create In-App Products matching your package IDs:
* In [Google Play Console](https://play.google.com/console) ➔ **Monetize** ➔ **In-app products**:
  * Product ID: `pack_500_rs` ➔ Price: Rs. 500 (Consumable)
  * Product ID: `pack_1000_rs` ➔ Price: Rs. 1,000 (Consumable)
  * Product ID: `pack_2500_rs` ➔ Price: Rs. 2,500 (Consumable)
  * Product ID: `pack_5000_rs` ➔ Price: Rs. 5,000 (Consumable)
* In [Apple App Store Connect](https://appstoreconnect.apple.com) ➔ **In-App Purchases** ➔ Create the same consumable products.

### Step 3: Handling Purchase Stream in Flutter
```dart
import 'package:in_app_purchase/in_app_purchase.dart';

final InAppPurchase _iap = InAppPurchase.instance;

// 1. Listen to purchase updates
_iap.purchaseStream.listen((List<PurchaseDetails> purchaseDetailsList) {
  for (final purchaseDetails in purchaseDetailsList) {
    if (purchaseDetails.status == PurchaseStatus.purchased) {
      // 2. Deliver coins via Supabase
      _deliverCoins(purchaseDetails);
    }
  }
});

// 2. Buy product
void buyPackage(String productId) async {
  final ProductDetailsResponse response = await _iap.queryProductDetails({productId});
  if (response.productDetails.isNotEmpty) {
    final PurchaseParam purchaseParam = PurchaseParam(productDetails: response.productDetails.first);
    await _iap.buyConsumable(purchaseParam: purchaseParam);
  }
}
```

---

## 3. Option B: Local Pakistani Payment Gateways (Easypaisa, JazzCash, Safepay, PayFast)

For Web users or direct Android APK downloads, you can accept Pakistani Rupee payments directly:

### 1. **Safepay (Recommended for modern Flutter & Web in Pakistan)**
* Supports **Debit/Credit Cards, Easypaisa, and JazzCash** in a single checkout.
* Sign up at [getsafepay.com](https://getsafepay.com).
* Get your API Public & Secret Keys.
* Flutter plugin: `safepay_flutter` or launch Safepay Checkout URL via webview / browser.

### 2. **PayFast (APPS) / Kuickpay**
* Official State Bank regulated gateway for Pakistan.
* Supports **1Link 1Bill, Cards, JazzCash, Easypaisa**.
* Generates a payment invoice / checkout sheet for the user.

### 3. **JazzCash / Easypaisa Direct Merchant API**
* Register for a JazzCash Corporate Merchant account or Easypaisa Developer account.
* Use their REST API to initiate Mobile Account Payment (OTC / MPIN prompt on user's phone).

---

## 4. Option C: International Card Top-Up (Stripe)

For international debit/credit cards:
1. Create a [Stripe account](https://stripe.com).
2. Use **Stripe Checkout** or `flutter_stripe`:
   * User taps package (e.g. `pack_500_rs`).
   * Opens hosted Stripe Checkout URL or mobile bottom sheet.
   * On completion, Stripe notifies your Supabase backend via Webhook.

---

## 5. How Payment Delivers Coins to Supabase

To ensure users never lose coins and purchases cannot be faked:

1. **Supabase PostgreSQL Schema:**
   The `profiles` and `transactions` tables are already configured:
   ```sql
   -- Add coins RPC function
   CREATE OR REPLACE FUNCTION add_user_coins(
     p_user_id UUID,
     p_coins INT,
     p_price_rs INT,
     p_package_id TEXT,
     p_tx_ref TEXT
   ) RETURNS VOID AS $$
   BEGIN
     -- Insert transaction audit record
     INSERT INTO transactions (user_id, package_id, coins, amount_rs, payment_ref)
     VALUES (p_user_id, p_package_id, p_coins, p_price_rs, p_tx_ref);

     -- Increment user coin balance
     UPDATE profiles
     SET coins = coins + p_coins
     WHERE id = p_user_id;
   END;
   $$ LANGUAGE plpgsql SECURITY DEFINER;
   ```

2. **Realtime UI Update:**
   When the transaction is verified and `profiles.coins` is updated in Supabase, the Supabase Realtime stream updates `_profile.coins` in [`home_screen.dart`](lib/features/home/home_screen.dart) and [`shop_modal.dart`](lib/features/shop/shop_modal.dart) **instantly in real-time**!
