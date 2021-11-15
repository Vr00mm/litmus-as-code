FROM ubuntu:20.04

LABEL maintainer "Rémi ZIOLKOWSKI (@Vr00mm) <remi.ziolkowski-ext@pole-emploi.fr>"
ARG KUBERNETES_VERSION=1.18.2
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get --yes update &&     apt-get --yes --no-install-recommends install curl jq openssl --option=Dpkg::Options::=--force-confdef && apt-get install --yes ca-certificates
RUN curl -sL -o /usr/local/bin/kubectl https://storage.googleapis.com/kubernetes-release/release/v${KUBERNETES_VERSION}/bin/linux/amd64/kubectl && chmod +x /usr/local/bin/kubectl

COPY functions.sh /functions.sh
COPY entrypoint.sh /entrypoint.sh
COPY litmusctl /usr/bin/litmusctl

ENTRYPOINT [ "/entrypoint.sh" ]
