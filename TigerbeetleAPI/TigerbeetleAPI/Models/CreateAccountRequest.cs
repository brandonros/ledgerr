using System.Text.Json.Serialization;

namespace TigerbeetleAPI.Models;

/// <summary>
/// Request model for /rpc/create_account endpoint
/// </summary>
public class CreateAccountRequest
{
    [JsonPropertyName("p_account_code")]
    public string AccountCode { get; set; } = string.Empty;

    [JsonPropertyName("p_account_name")]
    public string AccountName { get; set; } = string.Empty;

    [JsonPropertyName("p_account_type")]
    public string AccountType { get; set; } = string.Empty;

    [JsonPropertyName("p_parent_account_id")]
    public string? ParentAccountId { get; set; }

    [JsonPropertyName("p_account_id")]
    public string? AccountId { get; set; }
}