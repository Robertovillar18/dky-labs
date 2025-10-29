# Imagen base oficial de Python
FROM python:3.10-slim

# Crear carpeta de trabajo
WORKDIR /app

# Copiar archivos
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Variable de entorno para Flask
ENV PORT=8000

# Exponer puerto
EXPOSE 8000

# Comando de ejecución
CMD ["python", "app.py"]