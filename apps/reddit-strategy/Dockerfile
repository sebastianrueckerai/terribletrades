FROM python:3.12-slim

WORKDIR /app

# Copy requirements first for better caching
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy source code
COPY src/ ./src/

# Set the prompt file
COPY src/prompt.txt /app/prompt.txt

# Environment variables will be provided in deployment
ENV GROQ_MODEL_NAME=llama-3.3-70b-versatile
ENV PROMPT_FILE=/app/prompt.txt

# Run the app
CMD ["python", "src/strategy_worker.py"]
