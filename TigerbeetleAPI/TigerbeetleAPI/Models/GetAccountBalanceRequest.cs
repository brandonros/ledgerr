using System.Text.Json.Serialization;

namespace TigerbeetleAPI.Models;

/// <summary>
/// Request model for /rpc/get_account_balance endpoint
/// </summary>
public class GetAccountBalanceRequest
{
    [JsonPropertyName("p_account_id")]
    public string AccountId { get; set; } = string.Empty;

    [JsonPropertyName("p_as_of_date")]
    public DateTime? AsOfDate { get; set; }

    [JsonPropertyName("p_force_recalculate")]
    public bool ForceRecalculate { get; set; } = false;
}