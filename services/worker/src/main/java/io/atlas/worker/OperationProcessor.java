package io.atlas.worker;

import java.util.Map;
import java.util.UUID;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;

@Service
public class OperationProcessor {
    private final JdbcTemplate db;
    private final S3Client s3;
    private final ObjectMapper json;
    private final String bucket;
    public OperationProcessor(JdbcTemplate db, S3Client s3, ObjectMapper json, @Value("${atlas.report-bucket}") String bucket) {
        this.db = db; this.s3 = s3; this.json = json; this.bucket = bucket;
    }
    @Transactional
    public void process(String body) throws Exception {
        var event = json.readTree(body);
        if (event.path("version").asInt() != 1 || !event.path("type").asText().equals("OperationRequested"))
            throw new IllegalArgumentException("Unsupported event schema");
        var eventId = UUID.fromString(event.path("eventId").asText());
        var operationId = UUID.fromString(event.path("operationId").asText());
        int inserted = db.update("INSERT INTO processed_events(event_id) VALUES(?) ON CONFLICT DO NOTHING", eventId);
        if (inserted == 0) return;
        var op = db.queryForMap("SELECT * FROM operations WHERE id=? FOR UPDATE", operationId);
        if (!op.get("status").equals("queued")) return;
        var decision = PolicyEngine.evaluate((String)op.get("kind"), (String)op.get("region"), (String)op.get("classification"), (Integer)op.get("retention_days"));
        String reportKey = "reports/" + operationId + ".json";
        String report = json.writeValueAsString(Map.of("operationId", operationId, "eventId", eventId,
            "policyVersion", "1.0", "status", decision.status(), "explanation", decision.explanation(),
            "kind", op.get("kind"), "region", op.get("region"), "retentionDays", op.get("retention_days")));
        // Deterministic object name/content makes retries safe if S3 succeeds before the SQL transaction commits.
        s3.putObject(PutObjectRequest.builder().bucket(bucket).key(reportKey).contentType("application/json").build(), RequestBody.fromString(report));
        db.update("UPDATE operations SET status=?,decision=?,report_key=?,completed_at=now() WHERE id=?", decision.status(), decision.explanation(), reportKey, operationId);
        db.update("INSERT INTO audit(operation_id,action,detail) VALUES(?,?,?)", operationId, decision.status(), decision.explanation());
    }
}
