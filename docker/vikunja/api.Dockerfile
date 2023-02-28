FROM ubuntu:latest

WORKDIR /app/vikunja

RUN apt-get update
RUN apt-get install -y gpg unzip

ADD https://dl.vikunja.io/api/0.20.2/vikunja-v0.20.2-linux-amd64-full.zip ./
ADD https://dl.vikunja.io/api/0.20.2/vikunja-v0.20.2-linux-amd64-full.zip.asc ./

RUN gpg --keyserver keyserver.ubuntu.com --recv FF054DACD908493A
RUN gpg --verify vikunja-v0.20.2-linux-amd64-full.zip.asc vikunja-v0.20.2-linux-amd64-full.zip

RUN unzip vikunja-v0.20.2-linux-amd64-full.zip -d vikunja

ENTRYPOINT ["/app/vikunja/vikunja/vikunja-v0.20.2-linux-amd64"]