-- Provider credentials only; no health profiles, documents, transcripts or audio.
create schema if not exists lifetwin_private;
revoke all on schema lifetwin_private from public, anon, authenticated;

create table if not exists lifetwin_private.provider_usage (
  kind text not null check (kind in ('llm', 'voice')),
  window_start timestamptz not null,
  period text not null check (period in ('day', 'minute')),
  calls integer not null check (calls > 0),
  primary key (kind, window_start, period)
);
alter table lifetwin_private.provider_usage enable row level security;
revoke all on lifetwin_private.provider_usage from public, anon, authenticated;

create or replace function public.lifetwin_provider_config()
returns jsonb language sql security definer set search_path = ''
as $$
  select coalesce((select decrypted_secret::jsonb from vault.decrypted_secrets
    where name = 'lifetwin_backend_config' limit 1), '{}'::jsonb);
$$;
revoke all on function public.lifetwin_provider_config() from public, anon, authenticated;
grant execute on function public.lifetwin_provider_config() to service_role;

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
      'LLM_REASONING_EFFORT','PERSONALIZE_PROVIDER','ANTHROPIC_API_KEY','CLAUDE_MODEL',
      'CARTESIA_API_KEY','CARTESIA_VOICE_ID','CARTESIA_VERSION','CARTESIA_TTS_MODEL',
      'CARTESIA_STT_MODEL','CARTESIA_TTS_SPEED','CARTESIA_TOKEN_TTL_SECONDS',
      'ONBOARDING_DEMO','DOCUMENT_MUSE_ENABLED','LIFETWIN_CORS_ORIGINS'
    ])) then
    raise exception 'Unrecognized backend setting';
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

create or replace function public.lifetwin_take_provider_budget(provider_kind text)
returns boolean language plpgsql security definer set search_path = ''
as $$
declare accepted integer; cap integer;
begin
  if provider_kind not in ('llm', 'voice') or provider_kind is null then return false; end if;
  cap := case when provider_kind = 'llm' then 200 else 100 end;
  delete from lifetwin_private.provider_usage where window_start < now() - interval '2 days';
  insert into lifetwin_private.provider_usage(kind,window_start,period,calls)
    values(provider_kind,date_trunc('day',now() at time zone 'UTC') at time zone 'UTC','day',1)
    on conflict(kind,window_start,period) do update set calls = provider_usage.calls + 1
    where provider_usage.calls < cap returning calls into accepted;
  if accepted is null then return false; end if;
  accepted := null;
  insert into lifetwin_private.provider_usage(kind,window_start,period,calls)
    values(provider_kind,date_trunc('minute',now()),'minute',1)
    on conflict(kind,window_start,period) do update set calls = provider_usage.calls + 1
    where provider_usage.calls < 20 returning calls into accepted;
  return accepted is not null;
end;
$$;
revoke all on function public.lifetwin_take_provider_budget(text) from public, anon, authenticated;
grant execute on function public.lifetwin_take_provider_budget(text) to service_role;

-- Supabase's existing event-trigger helper is not an application RPC.
revoke execute on function public.rls_auto_enable() from public, anon, authenticated;
