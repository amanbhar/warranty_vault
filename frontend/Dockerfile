# Frontend: React (Vite)
# Production-ready Dockerfile for warranty_vault_web

FROM node:20

# Set working directory
WORKDIR /app

# Copy package files first for layer caching
COPY package.json package-lock.json ./

# Install dependencies
RUN npm install

# Copy application code
COPY . .

# Expose port 3006
EXPOSE 3006

# Start Vite dev server on port 3006
CMD ["npm", "run", "dev", "--", "--host", "0.0.0.0", "--port", "3006"]
