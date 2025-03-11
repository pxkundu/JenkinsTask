# Stage 1: Build the Node.js application
FROM node:18-slim AS builder
WORKDIR /app
COPY package*.json ./
RUN npm install  # Fixed typo: 'instal' to 'install'
COPY . .

# Stage 2: Use NGINX with Node.js
FROM nginx:alpine
# Copy Node.js app from builder stage
COPY --from=builder /app /usr/share/nginx/html/app
# Copy custom NGINX configuration
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Expose port 80
EXPOSE 80

# Start NGINX (Node.js will run inside the container via NGINX reverse proxy)
CMD ["nginx", "-g", "daemon off;"]
