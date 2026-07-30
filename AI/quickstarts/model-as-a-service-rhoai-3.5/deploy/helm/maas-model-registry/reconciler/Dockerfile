FROM registry.access.redhat.com/ubi9/python-311:latest

USER root

# Set working directory
WORKDIR /app

# Copy requirements and install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy reconciler code
COPY reconciler.py .

# Create cache directory for Hugging Face
RUN mkdir -p /tmp/hf_cache && chmod 777 /tmp/hf_cache

# Switch to non-root user
USER 1001

# Set environment variables
ENV PYTHONUNBUFFERED=1
ENV HF_HOME=/tmp/hf_cache

# Run the reconciler
CMD ["python", "reconciler.py"]

