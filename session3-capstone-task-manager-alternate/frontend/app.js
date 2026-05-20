const apiBaseUrl = window.APP_CONFIG?.apiBaseUrl?.replace(/\/$/, "") ?? "";
const taskForm = document.querySelector("#taskForm");
const statusSelect = document.querySelector("#status");
const tasksContainer = document.querySelector("#tasks");
const message = document.querySelector("#message");
const apiStatus = document.querySelector("#apiStatus");
const refreshButton = document.querySelector("#refreshButton");
let currentTasks = [];

function showMessage(text) {
  message.textContent = text;
  message.hidden = !text;
}

function setStatus(text, mode) {
  apiStatus.textContent = text;
  apiStatus.className = `status ${mode ?? ""}`.trim();
}

async function apiFetch(path, options = {}) {
  if (!apiBaseUrl || apiBaseUrl.includes("REPLACE-WITH")) {
    throw new Error("Update frontend/config.js with the deployed App Gateway URL.");
  }

  const response = await fetch(`${apiBaseUrl}${path}`, {
    headers: {
      "Content-Type": "application/json",
      ...(options.headers ?? {})
    },
    ...options
  });

  if (!response.ok) {
    const body = await response.text();
    throw new Error(body || `API request failed with status ${response.status}`);
  }

  if (response.status === 204) {
    return null;
  }

  return response.json();
}

async function loadLabels() {
  try {
    const labels = await apiFetch("/labels");
    statusSelect.innerHTML = labels
      .map(l => `<option value="${escapeHtml(l)}">${escapeHtml(l)}</option>`)
      .join("");
  } catch {
    // keep the default <option> already in the HTML
  }
}

function renderTasks(tasks) {
  currentTasks = tasks;

  if (!tasks.length) {
    tasksContainer.innerHTML = `<div class="task-card"><h3>No tasks yet</h3><p>Add the first task to verify the frontend, API, and Cosmos DB are connected.</p></div>`;
    return;
  }

  tasksContainer.innerHTML = tasks.map(task => `
    <article class="task-card" data-task-id="${escapeHtml(task.id)}">
      <h3>${escapeHtml(task.title)}</h3>
      <p>${escapeHtml(task.description || "No description provided.")}</p>
      <div class="task-meta">
        <span class="badge">${escapeHtml(task.status)}</span>
        <span>${new Date(task.createdAt).toLocaleString()}</span>
        <span>ID: ${escapeHtml(task.id)}</span>
      </div>
      <button type="button" class="delete-task-button" data-task-id="${escapeHtml(task.id)}" data-task-status="${escapeHtml(task.status)}">Delete</button>
    </article>
  `).join("");
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

async function loadTasks() {
  try {
    showMessage("");
    const tasks = await apiFetch("/tasks");
    renderTasks(tasks);
    setStatus("API connected", "ok");
  } catch (error) {
    setStatus("API unavailable", "error");
    showMessage(error.message);
    tasksContainer.innerHTML = "";
  }
}

async function deleteTask(id, status) {
  const task = currentTasks.find(item => item.id === id);
  const title = task?.title ?? id;

  if (!confirm(`Delete "${title}"?`)) {
    return;
  }

  try {
    showMessage("");
    await apiFetch(`/tasks/${encodeURIComponent(id)}?status=${encodeURIComponent(status)}`, {
      method: "DELETE"
    });

    renderTasks(currentTasks.filter(item => item.id !== id));
    setStatus("Task deleted", "ok");
  } catch (error) {
    showMessage(error.message);
  }
}

taskForm.addEventListener("submit", async event => {
  event.preventDefault();
  const formData = new FormData(taskForm);

  try {
    showMessage("");
    await apiFetch("/tasks", {
      method: "POST",
      body: JSON.stringify({
        title: formData.get("title"),
        description: formData.get("description"),
        status: formData.get("status")
      })
    });

    taskForm.reset();
    await loadTasks();
  } catch (error) {
    showMessage(error.message);
  }
});

refreshButton.addEventListener("click", loadTasks);
tasksContainer.addEventListener("click", event => {
  const deleteButton = event.target.closest(".delete-task-button");

  if (!deleteButton) {
    return;
  }

  deleteTask(deleteButton.dataset.taskId, deleteButton.dataset.taskStatus);
});

loadLabels();
loadTasks();
