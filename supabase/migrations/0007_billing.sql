-- PropertyOS — 0007_billing.sql
-- Store the Stripe customer + subscription for each org so webhooks
-- can map events back to the right organization.

alter table organizations
  add column if not exists stripe_customer_id text,
  add column if not exists stripe_subscription_id text;
