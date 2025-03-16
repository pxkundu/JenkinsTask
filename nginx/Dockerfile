FROM nginx:latest
COPY nginx.conf /etc/nginx/conf.d/default.conf
ENV VERSION="1.2.0"
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
