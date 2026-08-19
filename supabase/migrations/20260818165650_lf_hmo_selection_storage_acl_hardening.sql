-- CI push-event refresh; no runtime semantic change.
revoke truncate, references, trigger on public.lf_user_offer_selections from authenticated;
