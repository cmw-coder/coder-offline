FROM ghcr.io/coder/coder:v2.20.1

USER root

# 1. Create directory for the Terraform CLI (and assets)
# 2. Change repo source to private mirror
# 3. Update and install packages
RUN mkdir -p /opt/terraform \
    && sed -i 's|https://dl-cdn.alpinelinux.org|http://rdmirrors.h3c.com|g' /etc/apk/repositories \
    && apk update \
    && apk add curl unzip ca-certificates

# Add the H3C CA certificate to the system trust store
COPY ca-certs /usr/local/share/ca-certificates/
RUN update-ca-certificates

# Additionally, a Terraform mirror needs to be configured
# to download the Terraform providers used in Coder templates.
# There are two options:

# Option 1) Use a filesystem mirror.
#  We can seed this at build-time or by mounting a volume to
#  /opt/terraform/plugins in the container.
#  https://developer.hashicorp.com/terraform/cli/config/config-file#filesystem_mirror
#  Be sure to add all the providers you use in your templates to /opt/terraform/plugins

# Copy all offline packages to local registry
ADD mirrors /home/coder/.terraform.d/plugins/
ADD filesystem-mirror.tfrc /home/coder/.terraformrc

RUN chown -R coder:coder /home/coder/.terraform*
WORKDIR /home/coder

# Option 2) Use a network mirror.
#  https://developer.hashicorp.com/terraform/cli/config/config-file#network_mirror
#  Be sure uncomment line 60 and edit network-mirror-example.tfrc to
#  specify the HTTPS base URL of your mirror.

# ADD network-mirror-example.tfrc /home/coder/.terraformrc

USER coder

# Use the .terraformrc file to inform Terraform of the locally installed providers.
ENV TF_CLI_CONFIG_FILE=/home/coder/.terraformrc
