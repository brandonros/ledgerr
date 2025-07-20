using TigerbeetleAPI.Services;

var builder = WebApplication.CreateBuilder(args);

// Add services to the container
builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

// Register TigerBeetle service
builder.Services.AddSingleton<ITigerBeetleService, TigerBeetleService>();

// Configure JSON serialization to match PostgREST behavior
builder.Services.ConfigureHttpJsonOptions(options =>
{
    options.SerializerOptions.PropertyNamingPolicy = null; // Keep original property names
});

var app = builder.Build();

// Configure the HTTP request pipeline
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

// Remove HTTPS redirection to match PostgREST setup
// app.UseHttpsRedirection();

app.UseRouting();
app.MapControllers();

app.Run();
