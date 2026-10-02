FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY services/api/Atlas.Api.csproj services/api/packages.lock.json ./
RUN dotnet restore --locked-mode
COPY services/api/ ./
RUN dotnet publish -c Release --no-restore -o /app
FROM mcr.microsoft.com/dotnet/aspnet:10.0
WORKDIR /app
COPY --from=build /app .
COPY infra/certs/rds-ca.pem ./rds-ca.pem
RUN chown "$APP_UID:$APP_UID" /tmp
USER $APP_UID
VOLUME ["/tmp"]
ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080
ENTRYPOINT ["dotnet", "Atlas.Api.dll"]
