using System.Text.Json.Serialization;

namespace TigerbeetleAPI.Models;

/// <summary>
/// Represents a journal line type matching PostgreSQL ledgerr_api.journal_line_type
/// </summary>
public class JournalLineType
{
    [JsonPropertyName("account_id")]
    public string AccountId { get; set; } = string.Empty;

    [JsonPropertyName("debit_amount")]
    public decimal? DebitAmount { get; set; }

    [JsonPropertyName("credit_amount")]
    public decimal? CreditAmount { get; set; }

    [JsonPropertyName("description")]
    public string Description { get; set; } = string.Empty;
}