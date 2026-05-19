using Microsoft.Azure.Cosmos;
using System.Net;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();
builder.Services.AddApplicationInsightsTelemetry();
builder.Services.AddSingleton<TaskRepository>();

var allowedOrigins = builder.Configuration.GetSection("Cors:AllowedOrigins").Get<string[]>() ?? [];
builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy =>
    {
        if (allowedOrigins.Length > 0)
        {
            policy.WithOrigins(allowedOrigins).AllowAnyHeader().AllowAnyMethod();
        }
        else
        {
            policy.AllowAnyOrigin().AllowAnyHeader().AllowAnyMethod();
        }
    });
});

var app = builder.Build();

var enableSwagger = app.Configuration.GetValue("EnableSwagger", app.Environment.IsDevelopment());
if (enableSwagger)
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseHttpsRedirection();
app.UseCors();

app.MapGet("/", () => Results.Redirect("/swagger"))
    .ExcludeFromDescription();

app.MapGet("/health", () => Results.Ok(new { status = "healthy", timestamp = DateTimeOffset.UtcNow }))
    .WithName("Health")
    .WithSummary("Return API health status");

app.MapGet("/tasks", async (TaskRepository repository) =>
{
    var tasks = await repository.GetTasksAsync();
    return Results.Ok(tasks);
})
.WithName("GetTasks")
.WithSummary("Return all tasks")
.WithDescription("Reads all task items from Cosmos DB.")
.Produces<IReadOnlyList<TaskResponse>>(StatusCodes.Status200OK);

app.MapPost("/tasks", async (CreateTaskRequest request, TaskRepository repository) =>
{
    if (string.IsNullOrWhiteSpace(request.Title))
    {
        return Results.BadRequest(new { message = "Title is required." });
    }

    var task = await repository.CreateTaskAsync(request);
    return Results.Created($"/tasks/{task.Id}", task);
})
.WithName("CreateTask")
.WithSummary("Create a task")
.WithDescription("Adds a new task item to Cosmos DB.")
.Produces<TaskResponse>(StatusCodes.Status201Created)
.Produces(StatusCodes.Status400BadRequest);

app.MapDelete("/tasks/{id}", async (string id, string status, TaskRepository repository) =>
{
    var deleted = await repository.DeleteTaskAsync(id, status);
    return deleted ? Results.NoContent() : Results.NotFound(new { message = "Task not found." });
})
.WithName("DeleteTask")
.WithSummary("Delete a task")
.WithDescription("Stretch goal endpoint. Deletes a task by id and partition key status.")
.Produces(StatusCodes.Status204NoContent)
.Produces(StatusCodes.Status404NotFound);

app.Run();

public sealed record CreateTaskRequest(string Title, string? Description, string? Status);

public sealed record TaskResponse(string Id, string Title, string? Description, string Status, DateTimeOffset CreatedAt);

public sealed class TaskDocument
{
    public required string id { get; init; }
    public required string title { get; init; }
    public string? description { get; init; }
    public required string status { get; init; }
    public DateTimeOffset createdAt { get; init; }
}

public sealed class TaskRepository
{
    private readonly Container _container;

    public TaskRepository(IConfiguration configuration)
    {
        var connectionString = configuration["CosmosDb:ConnectionString"];
        var databaseName = configuration["CosmosDb:DatabaseName"] ?? "taskdb";
        var containerName = configuration["CosmosDb:ContainerName"] ?? "tasks";

        if (string.IsNullOrWhiteSpace(connectionString))
        {
            throw new InvalidOperationException("CosmosDb:ConnectionString is not configured. In Azure, Terraform sets this as a Key Vault reference resolved by the App Service managed identity.");
        }

        var client = new CosmosClient(connectionString);
        _container = client.GetContainer(databaseName, containerName);
    }

    public async Task<IReadOnlyList<TaskResponse>> GetTasksAsync()
    {
        var query = new QueryDefinition("SELECT c.id, c.title, c.description, c.status, c.createdAt FROM c ORDER BY c.createdAt DESC");
        using var iterator = _container.GetItemQueryIterator<TaskDocument>(query);
        var results = new List<TaskResponse>();

        while (iterator.HasMoreResults)
        {
            foreach (var task in await iterator.ReadNextAsync())
            {
                results.Add(ToResponse(task));
            }
        }

        return results;
    }

    public async Task<TaskResponse> CreateTaskAsync(CreateTaskRequest request)
    {
        var status = string.IsNullOrWhiteSpace(request.Status) ? "todo" : request.Status.Trim().ToLowerInvariant();
        var task = new TaskDocument
        {
            id = Guid.NewGuid().ToString("N"),
            title = request.Title.Trim(),
            description = request.Description,
            status = status,
            createdAt = DateTimeOffset.UtcNow
        };

        var response = await _container.CreateItemAsync(task, new PartitionKey(task.status));
        return ToResponse(response.Resource);
    }

    public async Task<bool> DeleteTaskAsync(string id, string status)
    {
        try
        {
            await _container.DeleteItemAsync<TaskDocument>(id, new PartitionKey(status));
            return true;
        }
        catch (CosmosException ex) when (ex.StatusCode == HttpStatusCode.NotFound)
        {
            return false;
        }
    }

    private static TaskResponse ToResponse(TaskDocument task) =>
        new(task.id, task.title, task.description, task.status, task.createdAt);
}
