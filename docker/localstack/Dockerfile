FROM mcr.microsoft.com/dotnet/sdk:8.0 AS notification-build

WORKDIR /src

COPY FCGNotification/NotificationsAPI/NotificationsAPI.csproj FCGNotification/NotificationsAPI/

RUN dotnet restore FCGNotification/NotificationsAPI/NotificationsAPI.csproj

COPY FCGNotification/NotificationsAPI/ FCGNotification/NotificationsAPI/

RUN dotnet publish FCGNotification/NotificationsAPI/NotificationsAPI.csproj \
    --configuration Release \
    --no-restore \
    --output /out/notification

RUN apt-get update \
    && apt-get install --yes --no-install-recommends zip \
    && cd /out/notification \
    && zip --recurse-paths /out/fcg-notification.zip . \
    && rm -rf /var/lib/apt/lists/*

FROM localstack/localstack:4.8.1

COPY --from=notification-build /out/fcg-notification.zip /opt/code/fcg-notification.zip
COPY FCGInfra/docker/localstack/init-notification.sh /etc/localstack/init/ready.d/10-init-notification.sh

RUN sed -i 's/\r$//' /etc/localstack/init/ready.d/10-init-notification.sh \
    && chmod +x /etc/localstack/init/ready.d/10-init-notification.sh
