using TigerbeetleAPI.Models;

namespace TigerbeetleAPI.Services;

/// <summary>
/// Interface for TigerBeetle operations
/// </summary>
public interface ITigerBeetleService
{
    /// <summary>
    /// Create a new account in TigerBeetle
    /// </summary>
    /// <param name="request">Account creation request</param>
    /// <returns>Account ID</returns>
    Task<string> CreateAccountAsync(CreateAccountRequest request);

    /// <summary>
    /// Record a journal entry (transfer) in TigerBeetle
    /// </summary>
    /// <param name="request">Journal entry request</param>
    /// <returns>Entry ID</returns>
    Task<string> RecordJournalEntryAsync(RecordJournalEntryRequest request);

    /// <summary>
    /// Get account balance from TigerBeetle
    /// </summary>
    /// <param name="request">Balance request</param>
    /// <returns>Account balance result</returns>
    Task<AccountBalanceResult> GetAccountBalanceAsync(GetAccountBalanceRequest request);
}