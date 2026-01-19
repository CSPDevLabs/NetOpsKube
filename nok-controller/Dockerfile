# Dockerfile
FROM python:3.9-slim-buster

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the controller script
COPY controller.py .

# Command to run the controller
CMD ["python", "controller.py"]