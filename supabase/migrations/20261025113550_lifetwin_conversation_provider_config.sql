-- Allow an explicit conversation provider without changing the other provider lanes.
create or replace function public.lifetwin_set_provider_config(p_config jsonb)
returns void language plpgsql security definer set search_path = ''
as $$
declare existing_id uuid;
begin
  if jsonb_typeof(p_config) <> 'object' or octet_length(p_config::text) > 65536 then
    raise exception 'Invalid backend configuration';
  end if;
  if exists (select 1 from jsonb_each(p_config) as setting
    where jsonb_typeof(setting.value) <> 'string' or setting.key <> all(array[
      'LLM_PROVIDER','LLM_BASE_URL','LLM_MODEL','LLM_API_KEY','LLM_ALLOW_CONTRIBUTOR',
      'LLM_REASONING_EFFORT','PERSONALIZE_PROVIDER','CONVERSATION_PROVIDER',
      'ANTHROPIC_API_KEY','CLAUDE_MODEL',
      'CARTESIA_API_KEY','CARTESIA_VOICE_ID','CARTESIA_VERSION','CARTESIA_TTS_MODEL',
      'CARTESIA_STT_MODEL','CARTESIA_TTS_SPEED','CARTESIA_TOKEN_TTL_SECONDS',
      'ONBOARDING_DEMO','DOCUMENT_MUSE_ENABLED','DOCUMENT_PROVIDER',
      'DOCUMENT_READ_TIMEOUT_SECONDS','API_MAX_PDF_BODY_BYTES','LIFETWIN_CORS_ORIGINS'
    ])) then
    raise exception 'Unrecognized backend setting';
  end if;
  if p_config ? 'CONVERSATION_PROVIDER' and
    p_config->>'CONVERSATION_PROVIDER' not in ('claude', 'muse', 'local') then
    raise exception 'Invalid conversation provider';
  end if;
  select id into existing_id from vault.secrets where name = 'lifetwin_backend_config';
  if existing_id is null then
    perform vault.create_secret(p_config::text, 'lifetwin_backend_config', 'LifeTwin provider configuration');
  else
    perform vault.update_secret(existing_id, p_config::text);
  end if;
end;
$$;
-- Provisioning is restricted to the database owner/MCP administrative connection.
revoke all on function public.lifetwin_set_provider_config(jsonb) from public, anon, authenticated, service_role;
