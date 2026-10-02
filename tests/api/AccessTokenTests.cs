using System.Security.Claims;
using Xunit;
public class AccessTokenTests
{
    [Theory]
    [InlineData("access", "atlas-web", "openid atlas/operate", "subject", true)]
    [InlineData("id", "atlas-web", "atlas/operate", "subject", false)]
    [InlineData("access", "another-client", "atlas/operate", "subject", false)]
    [InlineData("access", "atlas-web", "atlas/operate-all", "subject", false)]
    [InlineData("access", "atlas-web", "openid", "subject", false)]
    [InlineData("access", "atlas-web", "atlas/operate", "", false)]
    public void EnforcesCognitoAccessTokenPermissions(string type, string client, string scope, string subject, bool allowed)
    {
        var principal = new ClaimsPrincipal(new ClaimsIdentity(new[] { new Claim("token_use",type), new Claim("client_id",client), new Claim("scope",scope), new Claim("sub",subject) }));
        Assert.Equal(allowed, AccessTokenRules.Allows(principal,"atlas-web"));
    }
}
