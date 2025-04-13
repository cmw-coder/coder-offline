#!/bin/bash
if [ $# -ne 1 ]; then
    echo "- ? Usage: compose-up <docker-compose-file>"
    exit 1
fi

DOCKER_COMPOSE_FILE_PATH="$1"

export CODER_DERP_SERVER_REGION_ID="$(hostname -I | awk '{print $1}')"
export CODER_DERP_SERVER_RELAY_URL="http://$(hostname -I | awk '{print $1}'):7080"
export DOCKER_GROUP=$(getent group docker | cut -d: -f3)
docker compose -f "${DOCKER_COMPOSE_FILE_PATH}" up -d
