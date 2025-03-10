FROM ubuntu

ADD svn-co-progress /usr/local/bin
COPY ubuntu.sources /etc/apt/sources.list.d/

RUN chmod +x /usr/local/bin/svn-co-progress \
    && apt-get update \
    && apt-get install -y sudo curl locales language-pack-en-base nano vim subversion \
    && rm -rf /var/lib/apt/lists/* \
    && sed -i '/en_US.UTF-8/s/^#//g' /etc/locale.gen \
    && locale-gen en_US.UTF-8

ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

ARG USER=coder
RUN useradd --groups sudo --no-create-home --shell /bin/bash ${USER} \
    && echo "${USER} ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/${USER} \
    && chmod 0440 /etc/sudoers.d/${USER}

USER ${USER}
WORKDIR /home/${USER}
