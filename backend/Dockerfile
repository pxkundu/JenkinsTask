FROM node:20
WORKDIR /app
COPY package.json .
RUN npm install
COPY . .
EXPOSE 5000
ENV IMAGE_VERSION="v1.0.0"
CMD ["npm", "start"]
