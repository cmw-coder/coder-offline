FROM ubuntu

COPY --chmod=755 bin /usr/local/bin
COPY ubuntu.sources /etc/apt/sources.list.d/

RUN apt-get update \
    && apt-get install -y sudo ca-certificates curl locales language-pack-en-base nano vim subversion \
    && rm -rf /var/lib/apt/lists/* \
    && sed -i '/en_US.UTF-8/s/^#//g' /etc/locale.gen \
    && locale-gen en_US.UTF-8

# Add the H3C CA certificate to the system trust store
COPY ca-certs /usr/local/share/ca-certificates/
RUN update-ca-certificates

ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

ARG USER=coder
RUN useradd --groups sudo --no-create-home --shell /bin/bash ${USER} \
    && echo "${USER} ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/${USER} \
    && chmod 0440 /etc/sudoers.d/${USER}

USER ${USER}
WORKDIR /home/${USER}
