import uvicorn
from lifetwin.app import create_app
from lifetwin.core.config import Settings
settings=Settings(_env_file=None,app_env="test",rate_limit_per_minute=10000,openai_api_key="",llm_api_key="",anthropic_api_key="",cartesia_api_key="",tavily_api_key="",onboarding_demo=True)
uvicorn.run(create_app(settings),host="127.0.0.1",port=8134,access_log=False,log_level="warning")
