package io.atlas.worker;

import static org.junit.jupiter.api.Assertions.assertEquals;
import org.junit.jupiter.api.Test;

class PolicyEngineTest {
    @Test void validatesCompliantBackup() { assertEquals("validated", PolicyEngine.evaluate("backup", "us-east-1", "confidential", 365).status()); }
    @Test void rejectsShortBackupRetention() { assertEquals("rejected", PolicyEngine.evaluate("backup", "us-east-1", "internal", 29).status()); }
    @Test void rejectsConfidentialExport() { assertEquals("rejected", PolicyEngine.evaluate("data-export", "us-east-1", "confidential", 90).status()); }
    @Test void enforcesResidency() { assertEquals("rejected", PolicyEngine.evaluate("service-release", "eu-west-1", "confidential", 90).status()); }
    @Test void allowsInternalExport() { assertEquals("validated", PolicyEngine.evaluate("data-export", "eu-west-1", "internal", 90).status()); }
}
