#!/bin/bash
docker container rm coder_offline-coder-1
docker container rm coder_offline-database-1
docker image rm coder_offline-coder
docker volume rm coder_offline_coder_data
docker volume rm coder_offline_coder_home
