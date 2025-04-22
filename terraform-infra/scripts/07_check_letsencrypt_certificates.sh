#!/bin/bash

DOMAIN="tpcsonline.org"
SEVEN_DAYS_AGO=$(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S)

# On récupère l'output JSON filtré dans une variable
CERTS_LIST=$(curl -s "https://crt.sh/?q=%25.${DOMAIN}&output=json" | \
  jq --arg date_limit "$SEVEN_DAYS_AGO" '
    map(select(
      (.issuer_name | test("Let.s Encrypt")) and
      (.not_before >= $date_limit)
    ))
  '
)

# Nombre total de certificats
CERT_COUNT=$(echo "$CERTS_LIST" | jq 'length')

# Affichage
echo "Nombre de certificats Let's Encrypt émis pour $DOMAIN dans les 7 derniers jours : $CERT_COUNT"
echo
echo "Liste des certificats et date de délivrance :"
echo "$CERTS_LIST" | jq -r '
  .[] | "\(.common_name) | \(.not_before)"
'
echo
echo "Nombre de certificats Let's Encrypt émis pour $DOMAIN dans les 7 derniers jours : $CERT_COUNT"


# https://letsencrypt.org/docs/rate-limits/#new-certificates-per-registered-domain