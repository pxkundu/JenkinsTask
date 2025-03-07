FROM node:18-slim
WORKDIR /app
COPY package*.json ./
RUN npm instal
COPY . .
EXPOSE 80
CMD ["node", "app.js"]
