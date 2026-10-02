# Experiencia de proyecto

## Atlas Cloud Operations · Proyecto de ingeniería

Diseñé y desarrollé una plataforma para el gobierno y seguimiento de solicitudes operativas cloud, integrando una API en C# / ASP.NET Core, procesamiento asíncrono en Java / Spring Boot y una consola React con TypeScript.

Implementé consistencia transaccional con PostgreSQL y transactional outbox, comunicación SNS/SQS, deduplicación de eventos, evaluación de políticas y generación de evidencia JSON en S3. Incorporé autenticación, aislamiento de solicitudes por identidad y pruebas de concurrencia y del flujo distribuido.

Contenericé los componentes y configuré GitHub Actions para pruebas, integración, análisis de secretos, construcción y escaneo de imágenes, SBOM y procedencia. Preparé infraestructura Terraform para ECS Fargate, RDS Multi-AZ, Cognito, KMS, Secrets Manager, CloudFront, WAF, CloudTrail y observabilidad, con despliegue mediante OIDC y referencias de imágenes inmutables.

**Tecnologías:** C#, ASP.NET Core, Java 21, Spring Boot, React, TypeScript, PostgreSQL, Docker, GitHub Actions, Terraform y servicios AWS.

**Evidencia:** código público, historial Git, ejecución CI, imágenes OCI, pruebas distribuidas, decisiones de arquitectura y guía operativa.

## Texto breve

Desarrollo de Atlas Cloud Operations: plataforma de gobierno cloud con C#, Java y React, mensajería asíncrona, transactional outbox, idempotencia y auditoría. Contenedores y CI/CD con pruebas integradas, escaneo de imágenes e infraestructura AWS declarativa preparada para despliegue mediante OIDC.

## Alcance verificable

Presentar como proyecto propio de ingeniería/portafolio. La implementación y sus pruebas acreditan desarrollo práctico. La preparación de Terraform y del pipeline no acredita operación productiva en AWS, relación con clientes, empleo, certificación, SLA ni resultados de negocio. Añadir evidencia de despliegue y métricas cuando esas actividades se hayan realizado.
