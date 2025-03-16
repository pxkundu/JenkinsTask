FROM nginx:latest
COPY nginx.conf /etc/nginx/conf.d/default.conf
ENV NG_IMAGE_VERSION="v1.0.0"
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
