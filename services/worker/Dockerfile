FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /src
COPY services/worker/pom.xml ./
RUN mvn -B dependency:go-offline
COPY services/worker/src ./src
RUN mvn -B package -DskipTests
FROM eclipse-temurin:21-jre-jammy
RUN apt-get update && apt-get upgrade -y && rm -rf /var/lib/apt/lists/*
WORKDIR /app
RUN groupadd --gid 10001 atlas && useradd --uid 10001 --gid atlas --no-create-home atlas && chown atlas:atlas /tmp
COPY --from=build /src/target/policy-worker-1.0.0.jar app.jar
COPY infra/certs/rds-ca.pem ./rds-ca.pem
USER 10001:10001
VOLUME ["/tmp"]
EXPOSE 8081
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=70", "-jar", "app.jar"]
