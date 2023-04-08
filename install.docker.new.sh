#!/bin/bash

set -e

export NODE_OPTIONS="--openssl-legacy-provider --no-experimental-fetch"

echo "Node Version: $(node -v)"
echo "cURL Version: $(curl --version | head -n 1)"
echo "Docker Version: $(docker -v)"
echo "Docker Compose Version: $(docker compose version)"

# Disable Git-related functionality in buildx
export DOCKER_BUILDKIT=1
export BUILDKIT_PROGRESS=plain
export BUILDKIT_INLINE_CACHE=1
export BUILDKIT_ENABLE_LEGACY_GIT=0

# Check if the current user has permission to modify the necessary directories and files
if [ ! -w /var/run/docker.sock ] || [ ! -w "$(pwd)/docker/.env" ] || [ ! -w "$(pwd)/docker/data" ]; then
  echo "This script requires root privileges to modify some files and directories."
  exit 1
fi

if [ ! -f "$(pwd)/docker/.env" ]; then
  echo "Generating .env file..."
  ENV="develop"
  echo "Preparing your keys from https://my.telegram.org/"
  read -p "Enter your TG_API_ID: " TG_API_ID
  read -p "Enter your TG_API_HASH: " TG_API_HASH
  echo
  read -p "Enter your ADMIN_USERNAME: " ADMIN_USERNAME
  read -p "Enter your PORT: " PORT
  PORT="${PORT:=4000}"
  DB_PASSWORD=$(openssl rand -hex 16)
  echo "Generated random DB_PASSWORD: $DB_PASSWORD"
  echo
  echo "ENV=$ENV" > "$(pwd)/docker/.env"
  echo "PORT=$PORT" >> "$(pwd)/docker/.env"
  echo "TG_API_ID=$TG_API_ID" >> "$(pwd)/docker/.env"
  echo "TG_API_HASH=$TG_API_HASH" >> "$(pwd)/docker/.env"
  echo "ADMIN_USERNAME=$ADMIN_USERNAME" >> "$(pwd)/docker/.env"
  export DATABASE_URL=postgresql://postgres:$DB_PASSWORD@db:5432/teledrive
  echo "DB_PASSWORD=$DB_PASSWORD" >> "$(pwd)/docker/.env"
  if [ ! -d "$(pwd)/docker/data" ]; then
    mkdir -p "$(pwd)/docker/data"
    chown -R $(whoami):$(whoami) "$(pwd)/docker"
    chmod -R 777 "$(pwd)/docker"
  fi
  cd docker
  echo $DB_PASSWORD | sudo -S docker compose build teledrive
  echo $DB_PASSWORD | sudo -S docker compose up -d
  sleep 2
  echo $DB_PASSWORD | sudo -S docker compose exec teledrive yarn workspace api prisma migrate deploy
else
  cd docker
  git fetch origin
  if ! git rev-parse --verify staging >/dev/null 2>&1; then
    git branch staging origin/staging
  fi
  git checkout staging
  export $(cat "$(pwd)/docker/.env" | xargs)
  echo $DB_PASSWORD | sudo -S docker compose down
  echo $DB_PASSWORD | sudo -S docker compose up --build --force-recreate -d
  sleep 2
  echo $DB_PASSWORD | sudo -S docker compose up -d
  echo $DB_PASSWORD | sudo -S docker compose exec teledrive yarn workspace api prisma migrate deploy
  git reset --hard
  git clean -f
  git pull origin staging
fi
