# =============================================================================
# Dockerfile for Ikimina Tracker (Flask REST API)
# Build:  docker build -t ikimina-tracker .
# Run:    docker run -p 5000:5000 ikimina-tracker      (in-memory storage)
# Usually you start it with the database using:  docker compose up
# =============================================================================

# 1. Base image: a SPECIFIC Python version on a small ("slim") Debian image.
#    Pinning the tag means every build starts from the same Python, so the
#    image behaves the same on every laptop and in CI.
FROM python:3.12-slim

# 2. Python settings for containers:
#    - PYTHONDONTWRITEBYTECODE: don't create .pyc files (keeps image clean)
#    - PYTHONUNBUFFERED: print logs immediately so `docker logs` shows them live
#    - PIP_NO_CACHE_DIR / PIP_DISABLE_PIP_VERSION_CHECK: smaller image, quieter pip
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# 3. All following commands run inside /app (created automatically).
WORKDIR /app

# 4. Copy ONLY the requirements file first and install dependencies.
#    Docker caches each step ("layer"). Because requirements change rarely,
#    this slow step is reused on most rebuilds, even when the code changes.
COPY requirements.txt .
RUN pip install -r requirements.txt

# 5. Create an unprivileged user to run the app (security: if the app is ever
#    compromised, the attacker is not root inside the container).
#    --system: a service account with no password and no login shell.
#    A fixed numeric id (10001) lets tools verify the user is not root (uid 0).
RUN groupadd --system --gid 10001 app \
    && useradd --system --uid 10001 --gid app --no-create-home app

# 6. Copy the application code, owned by the new user.
#    Files listed in .dockerignore (tests, .git, venv, .env ...) are skipped.
COPY --chown=app:app app/ ./app/
COPY --chown=app:app run.py .

# 7. Switch to the non-root user (by id) for everything that runs from now on.
USER 10001

# 8. Document the port the app listens on (docker-compose maps it to the host).
EXPOSE 5000

# 9. Health check: Docker calls /health every 30s and marks the container
#    "unhealthy" if it stops answering. Uses Python's standard library
#    because curl is not installed in slim images (a failed request raises
#    an error, so python exits with 1 = unhealthy).
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:5000/health', timeout=4)"]

# 10. Start the app with Gunicorn, a production web server (Flask's built-in
#     server is only for development).
#     - 0.0.0.0: listen on all interfaces so traffic from outside the container arrives
#     - 2 workers: handle two requests at the same time
#     - --preload: create the app (and DB tables) once before starting workers
#     - run:app: the "app" object inside run.py
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "--preload", "--access-logfile", "-", "run:app"]
