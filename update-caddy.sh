#!/bin/bash

caddy fmt --overwrite
caddy adapt --validate > caddy.json
curl "http:localhost:2019/load" -H "Content-Type: application/json" -d @caddy.json
