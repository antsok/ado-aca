FROM ubuntu:22.04

RUN apt-get update && apt-get upgrade -y

RUN apt-get install -y -qq --no-install-recommends \
    ca-certificates \
    apt-transport-https \
    lsb-release

RUN apt-get install -y -qq --no-install-recommends \
    curl \
    wget \
    libicu70 \
    jq \
    git \
    iputils-ping \
    netcat

# Install latest powershell from Microsoft repo
RUN curl -sSL https://packages.microsoft.com/keys/microsoft.asc | tee /etc/apt/trusted.gpg.d/microsoft.asc && \
    wget -q https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb -O packages-microsoft-prod.deb && \
    dpkg -i packages-microsoft-prod.deb && rm packages-microsoft-prod.deb && \
    apt-get update && \
    apt-get install -y --no-install-recommends powershell && \
    rm -rf /var/lib/apt/lists/*

# Install latest azure-cli
RUN curl -LsS https://aka.ms/InstallAzureCLIDeb | bash \
  && rm -rf /var/lib/apt/lists/*

# Can be 'linux-x64', 'linux-arm64', 'linux-arm', 'rhel.6-x64'.
ENV TARGETARCH=linux-x64

WORKDIR /azp

COPY ./start.sh .
RUN chmod +x start.sh

ENTRYPOINT ["./start.sh"]