using Amazon;
using Amazon.SimpleNotificationService;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Npgsql;
using System.Security.Claims;
using System.Text.Json;

var builder = WebApplication.CreateBuilder(args);
builder.WebHost.ConfigureKestrel(o => o.Limits.MaxRequestBodySize = 16 * 1024);
var connection = builder.Configuration["DATABASE_URL"] ?? new NpgsqlConnectionStringBuilder
{
    Host = builder.Configuration["DB_HOST"] ?? throw new InvalidOperationException("DB_HOST is required"),
    Database = "atlas", Username = builder.Configuration["DB_USER"] ?? "atlasadmin",
    Password = builder.Configuration["DB_PASSWORD"] ?? throw new InvalidOperationException("DB_PASSWORD is required"),
    SslMode = SslMode.VerifyFull, RootCertificate = "/app/rds-ca.pem"
}.ConnectionString;
builder.Services.AddSingleton(NpgsqlDataSource.Create(connection));
builder.Services.AddSingleton<RequestStore>();
var local = builder.Environment.IsDevelopment();
if (local && string.IsNullOrWhiteSpace(builder.Configuration["DEV_API_TOKEN"]))
    throw new InvalidOperationException("DEV_API_TOKEN is required in Development");
if (!local)
{
    var issuer = builder.Configuration["OIDC_ISSUER"] ?? throw new InvalidOperationException("OIDC_ISSUER is required");
    var client = builder.Configuration["OIDC_CLIENT_ID"] ?? throw new InvalidOperationException("OIDC_CLIENT_ID is required");
    builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme).AddJwtBearer(o =>
    {
        o.Authority = issuer;
        o.MapInboundClaims = false;
        o.TokenValidationParameters.ValidateAudience = false; // Cognito access tokens identify the app via client_id.
        o.TokenValidationParameters.NameClaimType = "sub";
        o.Events = new JwtBearerEvents
        {
            OnTokenValidated = context =>
            {
                var p = context.Principal!;
                if (!AccessTokenRules.Allows(p, client))
                    context.Fail("Invalid access token permissions");
                return Task.CompletedTask;
            }
        };
    });
    builder.Services.AddAuthorization();
}
builder.Services.AddSingleton<IAmazonSimpleNotificationService>(_ =>
{
    var endpoint = builder.Configuration["AWS_ENDPOINT_URL"];
    return string.IsNullOrEmpty(endpoint)
        ? new AmazonSimpleNotificationServiceClient(RegionEndpoint.GetBySystemName(builder.Configuration["AWS_REGION"] ?? "us-east-1"))
        : new AmazonSimpleNotificationServiceClient(new AmazonSimpleNotificationServiceConfig { ServiceURL = endpoint, AuthenticationRegion = "us-east-1" });
});
builder.Services.AddHostedService<OutboxPublisher>();
builder.Services.AddProblemDetails();
var app = builder.Build();
app.UseExceptionHandler();
if (!local) { app.UseAuthentication(); app.UseAuthorization(); }
app.Use(async (context, next) =>
{
    context.Response.Headers["X-Content-Type-Options"] = "nosniff";
    context.Response.Headers["Cache-Control"] = "no-store";
    if (context.Request.Path.StartsWithSegments("/api"))
    {
        if (local)
        {
            var expected = "Bearer " + builder.Configuration["DEV_API_TOKEN"];
            if (!System.Security.Cryptography.CryptographicOperations.FixedTimeEquals(
                System.Text.Encoding.UTF8.GetBytes(context.Request.Headers.Authorization.ToString()),
                System.Text.Encoding.UTF8.GetBytes(expected))) { context.Response.StatusCode = 401; return; }
            context.User = new ClaimsPrincipal(new ClaimsIdentity(new[] { new Claim("sub", "local-operator") }, "local"));
        }
        else if (context.User.Identity?.IsAuthenticated != true) { context.Response.StatusCode = 401; return; }
    }
    await next();
});
await app.Services.GetRequiredService<RequestStore>().Initialize();
app.MapGet("/health/live", () => Results.Ok(new { status = "alive" }));
app.MapGet("/health/ready", async (RequestStore store) =>
{
    try { await store.Check(); return Results.Ok(new { status = "ready" }); }
    catch (NpgsqlException) { return Results.StatusCode(503); }
});
app.MapGet("/api/requests", async (HttpContext c, RequestStore store) => Results.Ok(await store.List(Actor(c))));
app.MapGet("/api/requests/{id:guid}", async (Guid id, HttpContext c, RequestStore store) =>
{
    var item = await store.Find(id, Actor(c));
    return item is null ? Results.NotFound() : Results.Ok(item);
});
app.MapGet("/api/requests/{id:guid}/audit", async (Guid id, HttpContext c, RequestStore store) => Results.Ok(await store.Audit(id, Actor(c))));
app.MapPost("/api/requests", async (OperationInput input, HttpContext c, RequestStore store) =>
{
    var errors = OperationRules.Validate(input);
    var key = c.Request.Headers["Idempotency-Key"].ToString();
    if (key.Length is < 8 or > 128) errors["idempotencyKey"] = ["Use an Idempotency-Key of 8 to 128 characters."];
    if (errors.Count != 0) return Results.ValidationProblem(errors);
    var result = await store.Create(input, Actor(c), key);
    if (result.Conflict) return Results.Conflict(new { error = "Idempotency key already used with a different payload." });
    return Results.Json(result.Item, statusCode: result.Replayed ? 200 : 201);
});
app.Run();
static string Actor(HttpContext c) => c.User.FindFirstValue("sub") ?? c.User.FindFirstValue(ClaimTypes.NameIdentifier) ?? throw new InvalidOperationException("Missing subject");
public partial class Program;

public static class AccessTokenRules
{
    public static bool Allows(ClaimsPrincipal principal, string clientId) =>
        !string.IsNullOrWhiteSpace(principal.FindFirstValue("sub")) &&
        principal.FindFirstValue("token_use") == "access" && principal.FindFirstValue("client_id") == clientId &&
        (principal.FindFirstValue("scope") ?? "").Split(' ').Contains("atlas/operate");
}

public record OperationInput(string? Title, string? Kind, string? Region, string? Classification, int RetentionDays);
public static class OperationRules
{
    public static Dictionary<string, string[]> Validate(OperationInput i)
    {
        var errors = new Dictionary<string, string[]>();
        if (string.IsNullOrWhiteSpace(i.Title) || i.Title.Length > 120) errors["title"] = ["Title must contain 1 to 120 characters."];
        if (i.Kind is not ("backup" or "data-export" or "service-release")) errors["kind"] = ["Unsupported operation."];
        if (i.Region is not ("us-east-1" or "us-west-2" or "eu-west-1")) errors["region"] = ["Unsupported region."];
        if (i.Classification is not ("internal" or "confidential")) errors["classification"] = ["Unsupported classification."];
        if (i.RetentionDays is < 1 or > 3650) errors["retentionDays"] = ["Retention must be between 1 and 3650 days."];
        return errors;
    }
}
