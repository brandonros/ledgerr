using TigerBeetle;
using TigerbeetleAPI.Models;
using System.Security.Cryptography;
using System.Text;

namespace TigerbeetleAPI.Services;

/// <summary>
/// TigerBeetle service implementation
/// </summary>
public class TigerBeetleService : ITigerBeetleService, IDisposable
{
    private readonly Client _client;
    private readonly ILogger<TigerBeetleService> _logger;
    private readonly Dictionary<string, uint> _accountTypeCodes;

    public TigerBeetleService(IConfiguration configuration, ILogger<TigerBeetleService> logger)
    {
        _logger = logger;
        
        // Initialize TigerBeetle client
        var clusterID = UInt128.Zero; // Default cluster ID
        var addresses = new[] { configuration.GetValue<string>("TigerBeetle:Address") ?? "5000" };
        _client = new Client(clusterID, addresses);

        // Map PostgreSQL account types to TigerBeetle codes
        _accountTypeCodes = new Dictionary<string, uint>
        {
            { "ASSET", 100 },
            { "LIABILITY", 200 },
            { "EQUITY", 300 },
            { "REVENUE", 400 },
            { "EXPENSE", 500 }
        };
    }

    public async Task<string> CreateAccountAsync(CreateAccountRequest request)
    {
        try
        {
            // Validate account type
            if (!_accountTypeCodes.TryGetValue(request.AccountType.ToUpper(), out var baseCode))
            {
                throw new ArgumentException($"Invalid account type: {request.AccountType}. Must be one of: ASSET, LIABILITY, EQUITY, REVENUE, EXPENSE");
            }

            // Generate account ID from string UUID
            var accountId = ConvertUuidToUInt128(request.AccountId ?? Guid.NewGuid().ToString());

            // Parse account code to get sub-code
            if (!uint.TryParse(request.AccountCode, out var accountCodeNum))
            {
                throw new ArgumentException($"Account code must be numeric: {request.AccountCode}");
            }

            var account = new Account
            {
                Id = accountId,
                Ledger = 1, // Using ledger 1 for all accounts
                Code = (ushort)(baseCode + accountCodeNum), // Combine base code with account code
                Flags = AccountFlags.None
            };

            var result = await Task.Run(() => _client.CreateAccounts(new[] { account }));
            
            if (result.Length > 0)
            {
                var error = result[0];
                throw new InvalidOperationException($"TigerBeetle account creation failed: {error.Result}");
            }

            _logger.LogInformation("Created account {AccountId} with code {Code}", accountId, account.Code);
            return ConvertUInt128ToUuid(accountId);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to create account {AccountCode}", request.AccountCode);
            throw;
        }
    }

    public async Task<string> RecordJournalEntryAsync(RecordJournalEntryRequest request)
    {
        try
        {
            // Validate the journal entry
            ValidateJournalEntry(request);

            // Generate deterministic transfer ID from idempotency key for proper idempotency
            var transferId = GenerateDeterministicId(request.IdempotencyKey);
            
            // Convert account IDs
            var debitAccountId = ConvertUuidToUInt128(request.DebitLine.AccountId);
            var creditAccountId = ConvertUuidToUInt128(request.CreditLine.AccountId);

            // Get the amount (should be the same for both debit and credit)
            // Convert decimal to cents (multiply by 100) since TigerBeetle works with integer amounts
            var amountDecimal = request.DebitLine.DebitAmount ?? request.CreditLine.CreditAmount ?? 0;
            var amount = (ulong)(amountDecimal * 100); // Convert to cents

            var transfer = new Transfer
            {
                Id = transferId,
                DebitAccountId = debitAccountId,
                CreditAccountId = creditAccountId,
                Amount = amount,
                Ledger = 1,
                Code = 1, // Default transfer code
                Flags = TransferFlags.None,
                Timestamp = 0 // Must be 0 for new transfers - TigerBeetle assigns timestamp and not (ulong)DateTimeOffset.UtcNow.ToUnixTimeSeconds() ?
            };

            var result = await Task.Run(() => _client.CreateTransfers(new[] { transfer }));
            
            if (result.Length > 0)
            {
                var error = result[0];
                
                // Check if this is a duplicate transfer (idempotency case)
                if (error.Result == CreateTransferResult.Exists)
                {
                    _logger.LogWarning("Transfer {TransferId} already exists (idempotency), returning existing ID", transferId);
                    return ConvertUInt128ToUuid(transferId);
                }
                
                throw new InvalidOperationException($"TigerBeetle transfer creation failed: {error.Result}");
            }

            _logger.LogDebug("Created transfer {TransferId} for {Amount}", transferId, amount);
            return ConvertUInt128ToUuid(transferId);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to record journal entry");
            throw;
        }
    }

    public async Task<AccountBalanceResult> GetAccountBalanceAsync(GetAccountBalanceRequest request)
    {
        try
        {
            var accountId = ConvertUuidToUInt128(request.AccountId);
            
            var accounts = await Task.Run(() => _client.LookupAccounts(new[] { accountId }));
            
            if (accounts.Length == 0)
            {
                throw new ArgumentException($"Account not found: {request.AccountId}");
            }

            var account = accounts[0];
            
            // Calculate balance based on account type
            // TigerBeetle stores debits_posted and credits_posted in cents, convert back to dollars
            var balance = (decimal)(long)(account.DebitsPosted - account.CreditsPosted) / 100;
            
            return new AccountBalanceResult
            {
                AccountBalance = balance,
                TotalDebits = (decimal)account.DebitsPosted / 100,
                TotalCredits = (decimal)account.CreditsPosted / 100,
                TransactionCount = 0, // TigerBeetle doesn't directly provide this
                LastActivityDate = null // Would need transfer history to determine this
            };
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to get account balance for {AccountId}", request.AccountId);
            throw;
        }
    }

    private void ValidateJournalEntry(RecordJournalEntryRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.Description))
            throw new ArgumentException("Description cannot be empty");

        if (string.IsNullOrWhiteSpace(request.IdempotencyKey))
            throw new ArgumentException("Idempotency key is required");

        // Validate debit line
        if (request.DebitLine.DebitAmount == null || request.DebitLine.DebitAmount <= 0)
            throw new ArgumentException("Debit line must have a positive debit amount");

        if (request.DebitLine.CreditAmount != null && request.DebitLine.CreditAmount != 0)
            throw new ArgumentException("Debit line cannot have a credit amount");

        // Validate credit line
        if (request.CreditLine.CreditAmount == null || request.CreditLine.CreditAmount <= 0)
            throw new ArgumentException("Credit line must have a positive credit amount");

        if (request.CreditLine.DebitAmount != null && request.CreditLine.DebitAmount != 0)
            throw new ArgumentException("Credit line cannot have a debit amount");

        // Validate amounts balance
        if (request.DebitLine.DebitAmount != request.CreditLine.CreditAmount)
            throw new ArgumentException($"Debit amount ({request.DebitLine.DebitAmount}) must equal credit amount ({request.CreditLine.CreditAmount}) - transaction not balanced");
    }

    private static UInt128 ConvertUuidToUInt128(string uuid)
    {
        var guid = Guid.Parse(uuid);
        var bytes = guid.ToByteArray();
        
        // Convert to UInt128 using byte array
        var low = BitConverter.ToUInt64(bytes, 0);
        var high = BitConverter.ToUInt64(bytes, 8);
        
        return new UInt128(high, low);
    }

    private static string ConvertUInt128ToUuid(UInt128 value)
    {
        var bytes = new byte[16];
        var low = (ulong)value;
        var high = (ulong)(value >> 64);
        
        Array.Copy(BitConverter.GetBytes(low), 0, bytes, 0, 8);
        Array.Copy(BitConverter.GetBytes(high), 0, bytes, 8, 8);
        
        return new Guid(bytes).ToString();
    }

    private static UInt128 GenerateDeterministicId(string idempotencyKey)
    {
        // Generate a deterministic UInt128 from the idempotency key using SHA256
        using var sha256 = SHA256.Create();
        var keyBytes = Encoding.UTF8.GetBytes(idempotencyKey);
        var hashBytes = sha256.ComputeHash(keyBytes);
        
        // Use first 16 bytes of the hash to create UInt128
        var low = BitConverter.ToUInt64(hashBytes, 0);
        var high = BitConverter.ToUInt64(hashBytes, 8);
        
        return new UInt128(high, low);
    }

    public void Dispose()
    {
        _client?.Dispose();
    }
}