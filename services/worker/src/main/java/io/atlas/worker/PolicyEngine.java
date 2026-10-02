package io.atlas.worker;

public final class PolicyEngine {
    private PolicyEngine() {}
    public record Decision(String status, String explanation) {}
    public static Decision evaluate(String kind, String region, String classification, int retentionDays) {
        if (classification.equals("confidential") && kind.equals("data-export"))
            return new Decision("rejected", "Confidential data requires an independent export approval.");
        if (kind.equals("backup") && retentionDays < 30)
            return new Decision("rejected", "Backup retention must be at least 30 days.");
        if (classification.equals("confidential") && !region.equals("us-east-1"))
            return new Decision("rejected", "Confidential records must remain in the approved primary region.");
        return new Decision("validated", "Operation satisfies the configured residency, retention and data-handling policies.");
    }
}
