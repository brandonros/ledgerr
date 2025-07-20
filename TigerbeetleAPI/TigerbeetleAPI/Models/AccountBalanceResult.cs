using System.Text.Json.Serialization;

namespace TigerbeetleAPI.Models;

/// <summary>
/// Represents account balance result matching PostgreSQL ledgerr_api.account_balance_result
/// </summary>
public class AccountBalanceResult
{
    [JsonPropertyName("account_balance")]
    public decimal AccountBalance { get; set; }

    [JsonPropertyName("total_debits")]
    public decimal TotalDebits { get; set; }

    [JsonPropertyName("total_credits")]
    public decimal TotalCredits { get; set; }

    [JsonPropertyName("transaction_count")]
    public long TransactionCount { get; set; }

    [JsonPropertyName("last_activity_date")]
    public DateTime? LastActivityDate { get; set; }
}