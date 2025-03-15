FROM node:20 AS build
WORKDIR /app
COPY package.json .
RUN npm install
COPY . .
RUN npm run build

FROM node:20
WORKDIR /app
RUN npm install -g serve
COPY --from=build /app/build .
EXPOSE 8080
CMD ["serve", "-s", ".", "-l", "8080"]