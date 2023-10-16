FROM ubuntu:latest
ARG version_arg=3
ENV VERSION=${version_arg}

RUN apt-get update
RUN apt-get install -y cowsay
CMD ["sh", "-c", "/usr/games/cowsay Hello World v$VERSION"]

# CMD ["/bin/sh", "-c", "echo Hello World v${VERSION}"]