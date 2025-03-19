FROM ubuntu

ENV LISTENING_PORT=7081
ENV EXTENSION_DIR=/opt/marketplace/extensions

RUN mkdir -p ${EXTENSION_DIR} && chmod -R 777 ${EXTENSION_DIR}
COPY --chmod=755 ./bin/code-marketplace /usr/local/bin

ENTRYPOINT code-marketplace server --address "0.0.0.0:${LISTENING_PORT}" --extensions-dir "${EXTENSION_DIR}"
