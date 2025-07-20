using Microsoft.AspNetCore.Mvc;
using TigerbeetleAPI.Models;
using TigerbeetleAPI.Services;

namespace TigerbeetleAPI.Controllers;

/// <summary>
/// RPC controller that mimics PostgREST endpoints
/// </summary>
[ApiController]
[Route("rpc")]
public class RpcController : ControllerBase
{
    private readonly ITigerBeetleService _tigerBeetleService;
    private readonly ILogger<RpcController> _logger;

    public RpcController(ITigerBeetleService tigerBeetleService, ILogger<RpcController> logger)
    {
        _tigerBeetleService = tigerBeetleService;
        _logger = logger;
    }

    /// <summary>
    /// Create a new account
    /// POST /rpc/create_account
    /// </summary>
    [HttpPost("create_account")]
    public async Task<ActionResult<string>> CreateAccount([FromBody] CreateAccountRequest request)
    {
        try
        {
            _logger.LogInformation("Creating account {AccountCode} of type {AccountType}", 
                request.AccountCode, request.AccountType);

            var accountId = await _tigerBeetleService.CreateAccountAsync(request);
            
            // Return the UUID as a quoted string to match PostgREST behavior
            return Ok($"\"{accountId}\"");
        }
        catch (ArgumentException ex)
        {
            _logger.LogWarning("Invalid request for create_account: {Error}", ex.Message);
            return BadRequest(new { message = ex.Message });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error creating account {AccountCode}", request.AccountCode);
            return StatusCode(500, new { message = "Internal server error" });
        }
    }

    /// <summary>
    /// Record a journal entry
    /// POST /rpc/record_journal_entry
    /// </summary>
    [HttpPost("record_journal_entry")]
    public async Task<ActionResult<string>> RecordJournalEntry([FromBody] RecordJournalEntryRequest request)
    {
        try
        {
            _logger.LogDebug("Recording journal entry with idempotency key {IdempotencyKey}", 
                request.IdempotencyKey);

            var entryId = await _tigerBeetleService.RecordJournalEntryAsync(request);
            
            // Return the UUID as a quoted string to match PostgREST behavior
            return Ok($"\"{entryId}\"");
        }
        catch (ArgumentException ex)
        {
            _logger.LogWarning("Invalid request for record_journal_entry: {Error}", ex.Message);
            return BadRequest(new { message = ex.Message });
        }
        catch (InvalidOperationException ex)
        {
            _logger.LogWarning("Business logic error in record_journal_entry: {Error}", ex.Message);
            return BadRequest(new { message = ex.Message });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error recording journal entry");
            return StatusCode(500, new { message = "Internal server error" });
        }
    }

    /// <summary>
    /// Get account balance
    /// POST /rpc/get_account_balance
    /// </summary>
    [HttpPost("get_account_balance")]
    public async Task<ActionResult<AccountBalanceResult>> GetAccountBalance([FromBody] GetAccountBalanceRequest request)
    {
        try
        {
            _logger.LogInformation("Getting balance for account {AccountId}", request.AccountId);

            var result = await _tigerBeetleService.GetAccountBalanceAsync(request);
            
            return Ok(result);
        }
        catch (ArgumentException ex)
        {
            _logger.LogWarning("Invalid request for get_account_balance: {Error}", ex.Message);
            return BadRequest(new { message = ex.Message });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting account balance for {AccountId}", request.AccountId);
            return StatusCode(500, new { message = "Internal server error" });
        }
    }
}