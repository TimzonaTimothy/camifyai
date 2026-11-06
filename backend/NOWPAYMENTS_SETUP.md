# NOWPayments USDT checkout

New crypto purchases use NOWPayments hosted checkout. The default network is USDT
on BNB Smart Chain (BEP20), currency code `usdtbsc`. USDT on TRON (`usdttrc20`) can
be used instead by configuring both the payment and payout currency to TRON. ERC20 is deliberately excluded from the configured choices.
USDT alone does not determine fees: the payment and payout networks both matter.

## Before accepting payments

1. In your NOWPayments merchant dashboard, add a **USDT BEP20 / BNB Smart Chain**
   payout wallet and select matching USDT settlement. A TRON or Ethereum address
   configuration is not interchangeable with a BEP20 payout configuration.
2. Set your API key and IPN secret in the backend environment. The IPN secret
   must match the secret used by your NOWPayments account.
3. Deploy the updated Django backend to a public HTTPS address reachable by
   NOWPayments. A private LAN address such as `10.x.x.x:8000` cannot receive IPN
   callbacks from NOWPayments. The desktop can still use a LAN backend for UI
   development, but live automatic settlement requires reachable callbacks to the
   **same database** that created the invoice.
4. Restart Django and rebuild/restart the desktop app. No new database fields or
   migrations are required.

```sh
export NOWPAYMENTS_API_KEY='your-merchant-api-key'
export NOWPAYMENTS_IPN_SECRET='your-merchant-ipn-secret'
export NOWPAYMENTS_CALLBACK_URL='https://your-public-backend/api/v1/payments/webhook/'
export NOWPAYMENTS_CURRENCIES='usdtbsc'
export NOWPAYMENTS_PAYOUT_CURRENCY='usdtbsc'
export NOWPAYMENTS_FEE_PAID_BY_USER='true'
```

`NOWPAYMENTS_PAYOUT_CURRENCY` is used for minimum-payment preflight and **must
match your actual merchant payout configuration**. It does not change your
merchant account or payout wallet automatically. The app offers only a network matching `NOWPAYMENTS_PAYOUT_CURRENCY` and rejects
cross-network invoice creation. To use TRON instead, configure both variables to
`usdttrc20` and change your actual merchant payout wallet/network accordingly.
These restrictions do not override your NOWPayments dashboard: select the same
asset there and check network-fee optimization settings if it routes to another
payout wallet. USD pack pricing and the estimate endpoint only calculate the
USDT quote; they do not initiate a currency exchange.

Customer-paid fees are enabled by default: the customer pays more than the pack
price. The billing screen discloses this before opening checkout. Fixed rate is
also enabled, as required for customer-paid fees. Set the fee flag to `false` to
absorb fees yourself; this does not remove blockchain or provider fees. Actual
payouts and fees remain subject to the provider quote and account configuration.
Nothing guarantees a zero-fee payment or an exact USD payout.

## Payment lifecycle

- Authenticated purchase: `POST /api/v1/auth/payments/create/` or
  `POST /api/v1/payments/create/`. Both call the same implementation.
- Enabled USDT networks and the fee policy come from
  `GET /api/v1/auth/payments/currencies/`.
- Before invoice creation, the backend requests the provider's live minimum and
  a crypto estimate. Packs below the current minimum are rejected without
  creating a provider invoice. Minimums are not hardcoded.
- Checkout uses an exact local order ID (`camify-<payment_id>`), a stored provider
  invoice ID, a server-controlled pack price, and the public IPN callback.
- `POST /api/v1/payments/webhook/` verifies HMAC SHA-512 over sorted JSON, then
  independently fetches payment details through the authenticated provider API.
- Credits are added only for **finished**, fully paid payments with matching
  invoice, order and USD price. `confirmed` is a deposit-confirmation stage;
  `partially_paid` does not grant a full pack.
- Payment and account-balance rows are locked when crediting. Repeated callbacks
  and polls cannot grant the same invoice twice.
- The desktop polls every 10 seconds while pending. Once a callback has associated
  the provider payment ID, polling can independently reconcile settlement too.
- A pending checkout can be reopened after restarting the desktop app. Returning
  from the hosted page never grants credits by itself.
- If callbacks are unavailable, the invoice remains pending; fix callback delivery
  or resend the IPN from the provider. Do not mark it paid based on a browser
  redirect or a screenshot. A duplicate valid finished callback is safe.

Existing manual payment records keep their proof-upload flow. New NOWPayments
records are marked as hosted checkouts and cannot use proof submission to bypass
provider verification. Historical invoices created by the removed legacy order
format need reconciliation separately; they are not matched by user/pack guesses.
Refunds of already credited orders require merchant review; the integration does
not automatically reverse credits that may already have been consumed.

## Verification

The automated tests use mocked provider responses and an isolated SQLite database.
They create no real invoices and make no real payments.

```sh
cd backend
python -m django test account.test_nowpayments --settings=account.nowpayments_test_settings
```

```sh
cd desktop
flutter test test/responsive_screens_test.dart
```

After deployment, verify your merchant wallet/network, callback accessibility,
checkout fee disclosure, payment minimums, and one controlled live payment before
rolling out the new checkout broadly. The live merchant configuration and actual
payout fees have not been tested by the automated suite.

Official references:
- [API endpoints](https://nowpayments.zendesk.com/hc/en-us/articles/21345824322717-API-and-endpoint-description)
- [Pricing and network fees](https://nowpayments.io/pricing)
- [Fee paid by user](https://nowpayments.io/blog/fee-paid-by-user)
- [IPN signature format](https://github.com/NowPaymentsIO/nowpayments-sdk-nodejs#webhooks--ipn)
