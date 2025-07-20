using System.Text.Json.Serialization;

namespace TigerbeetleAPI.Models;

/// <summary>
/// Request model for /rpc/record_journal_entry endpoint
/// </summary>
public class RecordJournalEntryRequest
{
    [JsonPropertyName("p_entry_date")]
    public DateTime EntryDate { get; set; }

    [JsonPropertyName("p_description")]
    public string Description { get; set; } = string.Empty;

    [JsonPropertyName("p_credit_line")]
    public JournalLineType CreditLine { get; set; } = new();

    [JsonPropertyName("p_debit_line")]
    public JournalLineType DebitLine { get; set; } = new();

    [JsonPropertyName("p_idempotency_key")]
    public string IdempotencyKey { get; set; } = string.Empty;

    [JsonPropertyName("p_reference_number")]
    public string? ReferenceNumber { get; set; }

    [JsonPropertyName("p_created_by")]
    public string CreatedBy { get; set; } = "system";
}