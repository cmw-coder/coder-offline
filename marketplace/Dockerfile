FROM ubuntu

USER root

COPY bin /usr/local/bin

ARG EXTENSION_DIR=/opt/marketplace/extensions
RUN mkdir -p ${EXTENSION_DIR} \
    && chmod -R 777 ${EXTENSION_DIR} \
    && chmod +x /usr/local/bin/code-marketplace

ARG PORT=7081
EXPOSE ${PORT}
RUN code-marketplace server --address "0.0.0.0:${PORT}" --extensions-dir ${EXTENSION_DIR}
