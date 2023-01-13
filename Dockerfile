FROM nginx:1.23.2

RUN mkdir -p /var/lib/nginx/pypi/ /var/log/nginx/ /var/run/
ADD nginx.conf /etc/nginx/nginx.conf
