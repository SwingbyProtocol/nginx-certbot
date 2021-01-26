#!/bin/bash

if ! [ -x "$(command -v docker-compose)" ]; then
  echo 'Error: docker-compose is not installed.' >&2
  exit 1
fi

rsa_key_size=4096
nginx_template_path="./nginx"
staging=0 # Set to 1 if you're testing your setup to avoid hitting request limits

mydomain=$DOMAIN
forward=$FORWARD
email=$EMAIL # Adding a valid address is strongly recommended
http_port=$PORT
data_path=$DIR
withIndexer=$WITH_IDNEXERS

nginx_mount_path="$data_path/nginx"
certbot_mount_path="$data_path/certbot"
mkdir -p $nginx_mount_path

cp "$nginx_template_path/http.conf" "$nginx_mount_path/$mydomain.conf"
sed -i "s/_DOMAIN_/$mydomain/g" "$nginx_mount_path/$mydomain.conf"
sed -i "s/_FORWARD_/$forward/g" "$nginx_mount_path/$mydomain.conf"
sed -i "s/_PORT_/$http_port/g" "$nginx_mount_path/$mydomain.conf"

domains=($mydomain)

btc_indexer="btc-indexer-$mydomain"
eth_indexer="eth-indexer-$mydomain"

if [[ "$withIndexer" == "false" ]]; then
  rm -f "$nginx_mount_path/$btc_indexer.conf"
  rm -f "$nginx_mount_path/$eth_indexer.conf"
fi

if [[ "$withIndexer" == "true" ]]; then
  domains=($mydomain $btc_indexer $eth_indexer)
  cp "$nginx_template_path/indexer.conf" "$nginx_mount_path/$btc_indexer.conf"
  sed -i "s/_DOMAIN_/$btc_indexer/g" "$nginx_mount_path/$btc_indexer.conf"
  sed -i "s/_FORWARD_/10.2.0.1/g" "$nginx_mount_path/$btc_indexer.conf"
  sed -i "s/_PORT_/9130/g" "$nginx_mount_path/$btc_indexer.conf"

  cp "$nginx_template_path/indexer.conf" "$nginx_mount_path/$eth_indexer.conf"
  sed -i "s/_DOMAIN_/$eth_indexer/g" "$nginx_mount_path/$eth_indexer.conf"
  sed -i "s/_FORWARD_/10.2.0.1/g" "$nginx_mount_path/$eth_indexer.conf"
  sed -i "s/_PORT_/9131/g" "$nginx_mount_path/$eth_indexer.conf"
fi



for domain in "${domains[@]}"; do
  if [ -e "$certbot_mount_path/conf/live/$domain/cert.pem" ]; then
    echo "Existing data found for $domain. Process is skipped..."
    exit 0
  fi
done

if [ ! -e "$certbot_mount_path/conf/options-ssl-nginx.conf" ] || [ ! -e "$certbot_mount_path/conf/ssl-dhparams.pem" ]; then
  echo "### Downloading recommended TLS parameters ..."
  mkdir -p "$certbot_mount_path/conf"
  curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot-nginx/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf >"$certbot_mount_path/conf/options-ssl-nginx.conf"
  curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot/certbot/ssl-dhparams.pem >"$certbot_mount_path/conf/ssl-dhparams.pem"
  echo
fi

for domain in "${domains[@]}"; do
  echo "### Creating dummy certificate for $domain ..."
  path="/etc/letsencrypt/live/$domain"
  mkdir -p "$certbot_mount_path/conf/live/$domain"
  DIR=$data_path docker-compose run --rm --entrypoint "\
  openssl req -x509 -nodes -newkey rsa:$rsa_key_size -days 1\
    -keyout '$path/privkey.pem' \
    -out '$path/fullchain.pem' \
    -subj '/CN=localhost'" certbot
done
echo

echo "### Starting nginx ..."
docker-compose up --force-recreate -d nginx
echo

for domain in "${domains[@]}"; do
  echo "### Deleting dummy certificate for $domain ..."
  DIR=$data_path docker-compose run --rm --entrypoint "\
  rm -Rf /etc/letsencrypt/live/$domain && \
  rm -Rf /etc/letsencrypt/archive/$domain && \
  rm -Rf /etc/letsencrypt/renewal/$domain.conf" certbot
  echo
done

echo "### Requesting Let's Encrypt certificate for $domains ..."
#Join $domains to -d args
domain_args=""
for domain in "${domains[@]}"; do
  domain_args="$domain_args -d $domain"
done

# Select appropriate email arg
case "$email" in
"") email_arg="--register-unsafely-without-email" ;;
*) email_arg="--email $email" ;;
esac

# Enable staging mode if needed
if [ $staging != "0" ]; then staging_arg="--staging"; fi

for domain in "${domains[@]}"; do
  docker-compose run --rm --entrypoint "\
  certbot certonly --webroot -w /var/www/certbot \
    $staging_arg \
    $email_arg \
    -d $domain \
    --rsa-key-size $rsa_key_size \
    --agree-tos \
    --force-renewal" certbot
  echo
done

echo "### Reloading nginx ..."
docker-compose exec nginx nginx -s reload
