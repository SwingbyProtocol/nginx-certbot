# Boilerplate for nginx with Let’s Encrypt on docker-compose

> This repository is accompanied by a [step-by-step guide on how to
set up nginx and Let’s Encrypt with Docker](https://medium.com/@pentacent/nginx-and-lets-encrypt-with-docker-in-less-than-5-minutes-b4b8a60d3a71).


## Installation docker
```
$ chmod +x ./install_docker.sh && ./install_docker.sh
```
## Getting Started
- 1. Setup Domain A record on your DNS service provider.
- 2. Setup SSL certificate via Let's encrypt.
```
$ DIR="./data" DOMAIN={you_domain} FORWARD=172.17.0.1 PORT={app_port} WITH_IDNEXERS=true EMAIL={your_email} ./init-letsencrypt.sh
```
5. Run the server:
```
$ DIR="./data" docker-compose up -d
```

## License
All code in this repository is licensed under the terms of the `MIT License`. For further information please refer to the `LICENSE` file.
