using Npgsql;
using System.Text.Json;
using System.Security.Cryptography;
using System.Text;

public class RequestStore(NpgsqlDataSource db)
{
    public async Task Initialize()
    {
        await using var conn = await db.OpenConnectionAsync();
        await using var tx = await conn.BeginTransactionAsync();
        await using var cmd = new NpgsqlCommand("""
            SELECT pg_advisory_xact_lock(843216);
            CREATE TABLE IF NOT EXISTS operations (
              id uuid PRIMARY KEY, actor text NOT NULL, idempotency_key text NOT NULL, payload_hash text NOT NULL,
              title text NOT NULL, kind text NOT NULL, region text NOT NULL, classification text NOT NULL,
              retention_days integer NOT NULL, status text NOT NULL DEFAULT 'queued',
              report_key text, decision text, created_at timestamptz NOT NULL DEFAULT now(), completed_at timestamptz,
              UNIQUE(actor, idempotency_key));
            CREATE TABLE IF NOT EXISTS outbox (
              id uuid PRIMARY KEY, payload jsonb NOT NULL, published_at timestamptz, created_at timestamptz NOT NULL DEFAULT now());
            CREATE INDEX IF NOT EXISTS outbox_pending ON outbox(created_at) WHERE published_at IS NULL;
            CREATE TABLE IF NOT EXISTS processed_events (event_id uuid PRIMARY KEY, processed_at timestamptz NOT NULL DEFAULT now());
            CREATE TABLE IF NOT EXISTS audit (
              id bigserial PRIMARY KEY, operation_id uuid NOT NULL REFERENCES operations(id), action text NOT NULL,
              detail text NOT NULL, created_at timestamptz NOT NULL DEFAULT now());
            CREATE INDEX IF NOT EXISTS audit_operation ON audit(operation_id, id);
            """, conn, tx);
        await cmd.ExecuteNonQueryAsync();
        await tx.CommitAsync();
    }
    public async Task Check() { await using var c = db.CreateCommand("SELECT 1"); await c.ExecuteScalarAsync(); }
    public async Task<CreateResult> Create(OperationInput input, string actor, string key)
    {
        var hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(JsonSerializer.Serialize(input))));
        var id = Guid.NewGuid(); var eventId = Guid.NewGuid();
        await using var conn = await db.OpenConnectionAsync();
        await using var tx = await conn.BeginTransactionAsync();
        await using var cmd = new NpgsqlCommand("""
            INSERT INTO operations(id,actor,idempotency_key,payload_hash,title,kind,region,classification,retention_days)
            VALUES(@id,@actor,@key,@hash,@title,@kind,@region,@classification,@retention)
            ON CONFLICT(actor,idempotency_key) DO NOTHING;
            """, conn, tx);
        cmd.Parameters.AddWithValue("id", id); cmd.Parameters.AddWithValue("actor", actor);
        cmd.Parameters.AddWithValue("key", key); cmd.Parameters.AddWithValue("hash", hash);
        cmd.Parameters.AddWithValue("title", input.Title!.Trim()); cmd.Parameters.AddWithValue("kind", input.Kind!);
        cmd.Parameters.AddWithValue("region", input.Region!); cmd.Parameters.AddWithValue("classification", input.Classification!);
        cmd.Parameters.AddWithValue("retention", input.RetentionDays);
        var inserted = await cmd.ExecuteNonQueryAsync() == 1;
        if (inserted)
        {
            var payload = JsonSerializer.Serialize(new { eventId, operationId = id, version = 1, type = "OperationRequested" });
            await using var write = new NpgsqlCommand("INSERT INTO outbox(id,payload) VALUES(@eid,@payload::jsonb); INSERT INTO audit(operation_id,action,detail) VALUES(@id,'requested','Request accepted for policy validation');", conn, tx);
            write.Parameters.AddWithValue("eid", eventId); write.Parameters.AddWithValue("payload", payload); write.Parameters.AddWithValue("id", id);
            await write.ExecuteNonQueryAsync();
        }
        await tx.CommitAsync();
        await using var find = db.CreateCommand("SELECT id,payload_hash FROM operations WHERE actor=@actor AND idempotency_key=@key");
        find.Parameters.AddWithValue("actor", actor); find.Parameters.AddWithValue("key", key);
        Guid storedId; string storedHash;
        await using (var reader = await find.ExecuteReaderAsync()) { await reader.ReadAsync(); storedId = reader.GetGuid(0); storedHash = reader.GetString(1); }
        return new(await Find(storedId, actor), !inserted, storedHash != hash);
    }
    public async Task<List<OperationView>> List(string actor)
    {
        await using var cmd = db.CreateCommand("SELECT id,title,kind,region,classification,retention_days,status,report_key,decision,created_at,completed_at FROM operations WHERE actor=@actor ORDER BY created_at DESC LIMIT 100");
        cmd.Parameters.AddWithValue("actor", actor);
        var list = new List<OperationView>(); await using var r = await cmd.ExecuteReaderAsync();
        while (await r.ReadAsync()) list.Add(Read(r)); return list;
    }
    public async Task<OperationView?> Find(Guid id, string actor)
    {
        await using var cmd = db.CreateCommand("SELECT id,title,kind,region,classification,retention_days,status,report_key,decision,created_at,completed_at FROM operations WHERE id=@id AND actor=@actor");
        cmd.Parameters.AddWithValue("id", id); cmd.Parameters.AddWithValue("actor", actor);
        await using var r = await cmd.ExecuteReaderAsync(); return await r.ReadAsync() ? Read(r) : null;
    }
    public async Task<List<AuditView>> Audit(Guid id, string actor)
    {
        await using var cmd = db.CreateCommand("SELECT a.action,a.detail,a.created_at FROM audit a JOIN operations o ON o.id=a.operation_id WHERE o.id=@id AND o.actor=@actor ORDER BY a.id");
        cmd.Parameters.AddWithValue("id", id); cmd.Parameters.AddWithValue("actor", actor);
        var result = new List<AuditView>(); await using var r = await cmd.ExecuteReaderAsync();
        while (await r.ReadAsync()) result.Add(new(r.GetString(0), r.GetString(1), r.GetDateTime(2))); return result;
    }
    private static OperationView Read(NpgsqlDataReader r) => new(r.GetGuid(0),r.GetString(1),r.GetString(2),r.GetString(3),r.GetString(4),r.GetInt32(5),r.GetString(6),r.IsDBNull(7)?null:r.GetString(7),r.IsDBNull(8)?null:r.GetString(8),r.GetDateTime(9),r.IsDBNull(10)?null:r.GetDateTime(10));
}
public record OperationView(Guid Id, string Title, string Kind, string Region, string Classification, int RetentionDays, string Status, string? ReportKey, string? Decision, DateTime CreatedAt, DateTime? CompletedAt);
public record AuditView(string Action, string Detail, DateTime CreatedAt);
public record CreateResult(OperationView? Item, bool Replayed, bool Conflict);
