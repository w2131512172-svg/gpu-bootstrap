const promptInput = document.getElementById("prompt");
const generateButton = document.getElementById("generate");
const generationState = document.getElementById("generation-state");
const resultGrid = document.getElementById("result-grid");
const historyGrid = document.getElementById("history-grid");
const refreshHistoryButton = document.getElementById("refresh-history");
const errorMessage = document.getElementById("error-message");
const healthDot = document.getElementById("health-dot");
const healthText = document.getElementById("health-text");
const viewer = document.getElementById("viewer");
const viewerImage = document.getElementById("viewer-image");
const closeViewerButton = document.getElementById("close-viewer");

let pollTimer = null;

function setState(text, mode = "idle") {
  generationState.textContent = text;
  generationState.dataset.mode = mode;
}

function showError(message = "") {
  errorMessage.textContent = message;
}

function imageButton(image, className) {
  const button = document.createElement("button");
  button.type = "button";
  button.className = className;
  button.setAttribute("aria-label", `查看 ${image.filename}`);
  const img = document.createElement("img");
  img.src = image.url;
  img.alt = image.filename;
  img.loading = "lazy";
  button.appendChild(img);
  button.addEventListener("click", () => {
    viewerImage.src = image.url;
    viewer.showModal();
  });
  return button;
}

function renderWaiting(items) {
  resultGrid.replaceChildren();
  for (const item of items) {
    const card = document.createElement("div");
    card.className = "waiting-card";
    const spinner = document.createElement("span");
    spinner.className = "spinner";
    const label = document.createElement("span");
    label.textContent = `图片 ${item.index} 正在生成`;
    card.append(spinner, label);
    resultGrid.appendChild(card);
  }
}

function renderResults(results) {
  const images = results.flatMap((result) => result.images || []);
  if (!images.length) return;
  resultGrid.replaceChildren();
  for (const image of images) {
    resultGrid.appendChild(imageButton(image, "result-card"));
  }
}

async function pollResults(items) {
  const query = new URLSearchParams();
  for (const item of items) query.append("prompt_id", item.prompt_id);
  try {
    const response = await fetch(`/api/results?${query.toString()}`, { cache: "no-store" });
    const data = await response.json();
    if (!response.ok || !data.ok) throw new Error(data.error || "读取结果失败");
    renderResults(data.results);
    const failed = data.results.some((item) => item.status === "failed");
    const finished = data.results.every((item) => ["completed", "failed"].includes(item.status));
    if (failed) {
      setState("部分任务失败", "error");
      showError("ComfyUI返回了失败状态，请检查工作流日志。");
    }
    if (finished) {
      clearInterval(pollTimer);
      pollTimer = null;
      if (!failed) setState("生成完成", "success");
      generateButton.disabled = false;
      await loadHistory();
    }
  } catch (error) {
    clearInterval(pollTimer);
    pollTimer = null;
    generateButton.disabled = false;
    setState("读取结果失败", "error");
    showError(error.message);
  }
}

async function generate() {
  const message = promptInput.value.trim();
  if (!message || generateButton.disabled) return;
  if (pollTimer) clearInterval(pollTimer);
  showError();
  generateButton.disabled = true;
  setState("正在调用Orchestrator", "running");
  resultGrid.innerHTML = '<div class="empty-state"><span class="spinner"></span><p>正在理解你的创作需求</p></div>';
  try {
    const response = await fetch("/api/generate", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ message, session_id: "main" }),
    });
    const data = await response.json();
    if (!response.ok || !data.ok) throw new Error(data.error || "任务提交失败");
    const items = data.result?.items || [];
    if (!items.length) throw new Error("Orchestrator没有返回prompt_id");
    renderWaiting(items);
    setState(`ComfyUI生成中 · ${items.length}张`, "running");
    await pollResults(items);
    if (!pollTimer && generateButton.disabled) {
      pollTimer = setInterval(() => pollResults(items), 1500);
    }
  } catch (error) {
    generateButton.disabled = false;
    setState("生成失败", "error");
    showError(error.message);
  }
}

async function loadHistory() {
  try {
    const response = await fetch("/api/history?limit=24", { cache: "no-store" });
    const data = await response.json();
    if (!response.ok || !data.ok) throw new Error(data.error || "读取历史失败");
    historyGrid.replaceChildren();
    if (!data.images.length) {
      const text = document.createElement("p");
      text.className = "muted";
      text.textContent = "ComfyUI暂时没有可显示的历史图片。";
      historyGrid.appendChild(text);
      return;
    }
    for (const image of data.images) {
      historyGrid.appendChild(imageButton(image, "history-card"));
    }
  } catch (error) {
    historyGrid.replaceChildren();
    const text = document.createElement("p");
    text.className = "muted";
    text.textContent = error.message;
    historyGrid.appendChild(text);
  }
}

async function checkHealth() {
  try {
    const response = await fetch("/api/health", { cache: "no-store" });
    const data = await response.json();
    const orchestrator = data.services?.orchestrator?.online;
    const comfyui = data.services?.comfyui?.online;
    healthDot.dataset.online = orchestrator && comfyui ? "true" : "false";
    healthText.textContent = orchestrator && comfyui ? "系统就绪" : "部分服务离线";
  } catch (_error) {
    healthDot.dataset.online = "false";
    healthText.textContent = "状态检查失败";
  }
}

generateButton.addEventListener("click", generate);
promptInput.addEventListener("keydown", (event) => {
  if (event.ctrlKey && event.key === "Enter") generate();
});
refreshHistoryButton.addEventListener("click", loadHistory);
closeViewerButton.addEventListener("click", () => viewer.close());
viewer.addEventListener("click", (event) => {
  if (event.target === viewer) viewer.close();
});

checkHealth();
loadHistory();
setInterval(checkHealth, 15000);
