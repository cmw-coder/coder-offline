FROM alpine:latest

ARG EXTENSION_DIR=/opt/marketplace/extensions
RUN mkdir -p ${EXTENSION_DIR} && chmod -R 777 ${EXTENSION_DIR}
COPY --chmod=755 --from=binaries ./bin/code-marketplace /usr/local/bin

ENV LISTENING_PORT=7081
CMD code-marketplace server --address "0.0.0.0:${LISTENING_PORT}" --extensions-dir "${EXTENSION_DIR}"
