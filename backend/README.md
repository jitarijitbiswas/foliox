# Backend

## Local development

```powershell
cd backend
python -m venv .venv
.venv\Scripts\pip install -e ".[dev]"
.venv\Scripts\uvicorn app.main:app --reload
```

OpenAPI is available at `http://127.0.0.1:8000/docs`; liveness is
`GET /api/v1/health`.

Module packages are added under `app/modules/<module>` and keep domain/application
code independent from framework and persistence details.

