using Amazon.SimpleNotificationService;
using Amazon.SimpleNotificationService.Model;
using Npgsql;

public sealed class OutboxPublisher(NpgsqlDataSource db, IAmazonSimpleNotificationService sns, IConfiguration config, ILogger<OutboxPublisher> log) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken token)
    {
        while (!token.IsCancellationRequested)
        {
            try
            {
                await using var conn = await db.OpenConnectionAsync(token);
                await using var tx = await conn.BeginTransactionAsync(token);
                Guid id = default; string? payload = null;
                await using (var cmd = new NpgsqlCommand("SELECT id,payload::text FROM outbox WHERE published_at IS NULL ORDER BY created_at LIMIT 1 FOR UPDATE SKIP LOCKED", conn, tx))
                await using (var r = await cmd.ExecuteReaderAsync(token))
                    if (await r.ReadAsync(token)) { id = r.GetGuid(0); payload = r.GetString(1); }
                if (payload is not null)
                {
                    await sns.PublishAsync(new PublishRequest { TopicArn = config["SNS_TOPIC_ARN"] ?? throw new InvalidOperationException("SNS_TOPIC_ARN is required"), Message = payload }, token);
                    await using var update = new NpgsqlCommand("UPDATE outbox SET published_at=now() WHERE id=@id", conn, tx);
                    update.Parameters.AddWithValue("id", id); await update.ExecuteNonQueryAsync(token);
                    log.LogInformation("Published event {EventId}", id);
                }
                await tx.CommitAsync(token);
                if (payload is null) await Task.Delay(1000, token);
            }
            catch (OperationCanceledException) when (token.IsCancellationRequested) { break; }
            catch (Exception ex) { log.LogError(ex, "Outbox delivery failed; retrying"); await Task.Delay(3000, token); }
        }
    }
}
