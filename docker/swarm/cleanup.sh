#!/bin/bash
docker service rm biblio_biblioapi
docker service rm biblio_bibliomongo
docker network rm biblio_default

