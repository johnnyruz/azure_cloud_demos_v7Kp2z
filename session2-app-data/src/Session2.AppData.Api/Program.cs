using Microsoft.Azure.Cosmos;
using System.Net;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();
builder.Services.AddApplicationInsightsTelemetry();
builder.Services.AddSingleton<CosmosItemRepository>();

var app = builder.Build();

var enableSwagger = app.Configuration.GetValue("EnableSwagger", app.Environment.IsDevelopment());
if (enableSwagger)
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseHttpsRedirection();

app.MapGet("/", () => Results.Redirect("/swagger"))
    .ExcludeFromDescription();

app.MapGet("/items", async (CosmosItemRepository repository) =>
{
    var items = await repository.GetItemsAsync();
    return Results.Ok(items);
})
.WithName("GetItems")
.WithSummary("Return all items")
.WithDescription("Reads all items from the configured Cosmos DB container.")
.Produces<IReadOnlyList<ItemResponse>>(StatusCodes.Status200OK);

app.MapPost("/items", async (CreateItemRequest request, CosmosItemRepository repository) =>
{
    if (string.IsNullOrWhiteSpace(request.Name))
    {
        return Results.BadRequest(new { message = "Name is required." });
    }

    var item = await repository.CreateItemAsync(request);
    return Results.Created($"/items/{item.Id}", item);
})
.WithName("CreateItem")
.WithSummary("Create an item")
.WithDescription("Adds a new item to the configured Cosmos DB container.")
.Produces<ItemResponse>(StatusCodes.Status201Created)
.Produces(StatusCodes.Status400BadRequest);

app.MapDelete("/items/{id}", async (string id, string category, CosmosItemRepository repository) =>
{
    var deleted = await repository.DeleteItemAsync(id, category);
    return deleted ? Results.NoContent() : Results.NotFound(new { message = "Item not found." });
})
.WithName("DeleteItem")
.WithSummary("Delete an item")
.WithDescription("Stretch goal endpoint. Deletes an item by id and partition key category.")
.Produces(StatusCodes.Status204NoContent)
.Produces(StatusCodes.Status404NotFound);

app.Run();

public sealed record CreateItemRequest(string Name, string Category, string? Description);

public sealed record ItemResponse(string Id, string Name, string Category, string? Description, DateTimeOffset CreatedAt);

public sealed class CosmosItem
{
    public required string id { get; init; }
    public required string name { get; init; }
    public required string category { get; init; }
    public string? description { get; init; }
    public DateTimeOffset createdAt { get; init; }
}

public sealed class CosmosItemRepository
{
    private readonly Container _container;

    public CosmosItemRepository(IConfiguration configuration)
    {
        var connectionString = configuration["CosmosDb:ConnectionString"];
        var databaseName = configuration["CosmosDb:DatabaseName"] ?? "trainingdb";
        var containerName = configuration["CosmosDb:ContainerName"] ?? "items";

        if (string.IsNullOrWhiteSpace(connectionString))
        {
            throw new InvalidOperationException("CosmosDb:ConnectionString is not configured. Set it with user-secrets locally or as an Azure App Setting named CosmosDb__ConnectionString.");
        }

        var client = new CosmosClient(connectionString);
        _container = client.GetContainer(databaseName, containerName);
    }

    public async Task<IReadOnlyList<ItemResponse>> GetItemsAsync()
    {
        var query = new QueryDefinition("SELECT c.id, c.name, c.category, c.description, c.createdAt FROM c ORDER BY c.createdAt DESC");
        using var iterator = _container.GetItemQueryIterator<CosmosItem>(query);
        var results = new List<ItemResponse>();

        while (iterator.HasMoreResults)
        {
            foreach (var item in await iterator.ReadNextAsync())
            {
                results.Add(ToResponse(item));
            }
        }

        return results;
    }

    public async Task<ItemResponse> CreateItemAsync(CreateItemRequest request)
    {
        var category = string.IsNullOrWhiteSpace(request.Category) ? "general" : request.Category.Trim().ToLowerInvariant();
        var item = new CosmosItem
        {
            id = Guid.NewGuid().ToString("N"),
            name = request.Name.Trim(),
            category = category,
            description = request.Description,
            createdAt = DateTimeOffset.UtcNow
        };

        var response = await _container.CreateItemAsync(item, new PartitionKey(item.category));
        return ToResponse(response.Resource);
    }

    public async Task<bool> DeleteItemAsync(string id, string category)
    {
        try
        {
            await _container.DeleteItemAsync<CosmosItem>(id, new PartitionKey(category));
            return true;
        }
        catch (CosmosException ex) when (ex.StatusCode == HttpStatusCode.NotFound)
        {
            return false;
        }
    }

    private static ItemResponse ToResponse(CosmosItem item) =>
        new(item.id, item.name, item.category, item.description, item.createdAt);
}
