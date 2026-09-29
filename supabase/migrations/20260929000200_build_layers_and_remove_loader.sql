-- Run after scripts/load_layers.py has filled private.staging.
-- Builds the layer tables and routing network, then removes the temporary loader.

call private.build_layers();

drop function public.stage_features(text, text, jsonb);
drop table private.load_token;
drop table private.staging;
