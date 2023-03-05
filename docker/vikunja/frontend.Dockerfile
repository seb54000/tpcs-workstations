FROM nginx:latest

WORKDIR /app

RUN apt-get update
RUN apt-get install -y unzip

ADD https://dl.vikunja.io/frontend/vikunja-frontend-0.20.3.zip ./
COPY frontend.nginx.conf /etc/nginx/conf.d/

RUN unzip vikunja-frontend-0.20.3.zip -d vikunja

COPY index.html vikunja/

