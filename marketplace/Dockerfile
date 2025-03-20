FROM ubuntu

COPY ubuntu.sources /etc/apt/sources.list.d/

ENV LISTENING_PORT=7081
ENV EXTENSION_DIR=/opt/marketplace/extensions

RUN apt-get update \
    && apt-get install -y curl ca-certificates \
    && mkdir -p ${EXTENSION_DIR} \
    && chmod -R 777 ${EXTENSION_DIR}

# Add the H3C CA certificate to the system trust store
COPY ca-certs /usr/local/share/ca-certificates/
RUN update-ca-certificates

COPY --chmod=755 ./bin/code-marketplace /usr/local/bin
ENTRYPOINT code-marketplace server --address "0.0.0.0:${LISTENING_PORT}" --extensions-dir "${EXTENSION_DIR}" --sign
