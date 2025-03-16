FROM node:20
WORKDIR /app
COPY package.json .
RUN npm install --production  # Optimize for production
COPY . .
# Added for pipeline test
ENV VERSION="1.1.0"
EXPOSE 5000
CMD ["node", "app.js"]