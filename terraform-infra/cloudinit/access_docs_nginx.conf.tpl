server {
        listen 80 default_server;
        listen [::]:80 default_server;

        root /var/www/html;
        index index.html index.htm index.nginx-debian.html;

        server_name access.${dns_subdomain} www.access.${dns_subdomain};
        location / {
                proxy_pass  https://127.0.0.1:8443;
                proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                proxy_set_header Host $host;
                proxy_http_version 1.1;
                proxy_set_header Upgrade $http_upgrade;
                proxy_set_header Connection "upgrade";
        }
}

server {
        listen 80;
        listen [::]:80;

        location /{
        root /var/www/html/;
        index index.html;
        autoindex on;
        charset utf-8;
        }

        server_name docs.${dns_subdomain} www.docs.${dns_subdomain};
        # pass PHP scripts on Nginx to FastCGI (PHP-FPM) server

        location ~ \.php$ {
                include snippets/fastcgi-php.conf;
                root /var/www/html/;
                # Nginx php-fpm sock config:
                fastcgi_pass unix:/run/php/php8.1-fpm.sock;
                # Nginx php-cgi config :
                # Nginx PHP fastcgi_pass 127.0.0.1:9000;
        }
}

server {
        listen 80;
        listen [::]:80;

        server_name monitoring.${dns_subdomain} www.monitoring.${dns_subdomain};
        location / {
                proxy_pass  http://127.0.0.1:3000;
                proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                proxy_set_header Host $host;
                proxy_http_version 1.1;
                proxy_set_header Upgrade $http_upgrade;
                proxy_set_header Connection "upgrade";
        }
}

server {
        listen 80;
        listen [::]:80;

        server_name prometheus.${dns_subdomain} www.prometheus.${dns_subdomain};
        location / {
                proxy_pass  http://127.0.0.1:9090;
                proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                proxy_set_header Host $host;
                proxy_http_version 1.1;
                proxy_set_header Upgrade $http_upgrade;
                proxy_set_header Connection "upgrade";
        }
}

server {
        listen 80;
        listen [::]:80;

        server_name grafana.${dns_subdomain} www.grafana.${dns_subdomain};
        location / {
                proxy_pass  http://127.0.0.1:3000;
                proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                proxy_set_header Host $host;
                proxy_http_version 1.1;
                proxy_set_header Upgrade $http_upgrade;
                proxy_set_header Connection "upgrade";
        }
}