-- PropertyOS — 0008_acquisition_send.sql
-- Track when an analysis was pushed to the Acquisition Engine.

alter table analyses
  add column if not exists sent_to_acquisition_at timestamptz,
  add column if not exists acquisition_deal_id text;
