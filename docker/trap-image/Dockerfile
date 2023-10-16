FROM ubuntu:latest

# ARG DEBIAN_FRONTEND=noninteractive

# RUN apt-get update

COPY trap.sh /usr/local/bin/trap.sh
RUN chmod 700 /usr/local/bin/trap.sh

ENTRYPOINT ["/usr/local/bin/trap.sh"]
# ENTRYPOINT ["exec", "/usr/local/bin/trap.sh"]