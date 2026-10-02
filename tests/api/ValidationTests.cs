using Xunit;
public class ValidationTests
{
    [Fact] public void AcceptsValidOperation() => Assert.Empty(OperationRules.Validate(new("Backup audit records", "backup", "us-east-1", "confidential", 365)));
    [Theory]
    [InlineData(0)] [InlineData(-1)] [InlineData(3651)]
    public void RejectsInvalidRetention(int days) => Assert.Contains("retentionDays", OperationRules.Validate(new("Backup", "backup", "us-east-1", "internal", days)).Keys);
    [Fact] public void RejectsUnknownRegionAndKind()
    {
        var errors = OperationRules.Validate(new("Request", "delete-account", "unknown", "public", 90));
        Assert.Contains("kind", errors.Keys); Assert.Contains("region", errors.Keys); Assert.Contains("classification", errors.Keys);
    }
    [Fact] public void RejectsBlankTitle() => Assert.Contains("title", OperationRules.Validate(new("  ", "backup", "us-east-1", "internal", 1)).Keys);
}
