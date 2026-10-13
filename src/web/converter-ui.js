import { showToast, formatBytes } from "./renderer.js";
import {
  SUPPORTED_FORMATS,
  isSupportedDocument,
  generateConversionPreview
} from "./converter.js";

// --- Element selectors ---
const $ = (id) => document.getElementById(id);
const navRenamer = $("nav-renamer");
const navConverter = $("nav-converter");
const viewRenamer = $("view-renamer");
const viewConverter = $("view-converter");
const windowTitle = $("window-title");

const sourceLabel = $("conv-source-label");
const outputLabel = $("conv-output-label");
const btnFiles = $("conv-btn-files");
const btnFolder = $("conv-btn-folder");
const btnOutput = $("conv-btn-output");
const btnOutputReset = $("conv-btn-output-reset");
const configCard = $("conv-config-card");
const targetSelect = $("conv-target");
const filterSelect = $("conv-filter");
const conflictSelect = $("conv-conflict");
const toolsHint = $("conv-tools-hint");
const countBadge = $("conv-count");
const emptyState = $("conv-empty");
const tableWrapper = $("conv-table-wrapper");
const tbody = $("conv-tbody");
const footer = $("conv-footer");
const summary = $("conv-summary");
const btnReveal = $("conv-btn-reveal");
const btnRun = $("conv-btn-run");

// --- State ---
let sourceFiles = [];       // [{name, path, directory, size}]
let outputDirectory = null; // null => same folder as source
let existingPaths = [];     // full paths already present in destination directories
let queue = [];
let busy = false;

// --- View switching (View Transitions API with graceful fallback) ---
function showView(name) {
  const isConverter = name === "converter";
  viewConverter.classList.toggle("hidden", !isConverter);
  viewRenamer.classList.toggle("hidden", isConverter);
  navConverter.classList.toggle("active", isConverter);
  navRenamer.classList.toggle("active", !isConverter);
  windowTitle.textContent = isConverter ? "Document Converter" : "File Renamer";
}

function switchView(name) {
  const target = name === "converter" ? viewConverter : viewRenamer;
  if (!document.startViewTransition) {
    showView(name);
    target.focus();
    return;
  }
  const transition = document.startViewTransition(() => showView(name));
  transition.finished.finally(() => target.focus());
}

navConverter.addEventListener("click", (e) => {
  e.preventDefault();
  if (viewConverter.classList.contains("hidden")) {
    switchView("converter");
    refreshToolHint();
  }
});
navRenamer.addEventListener("click", (e) => {
  e.preventDefault();
  if (viewRenamer.classList.contains("hidden")) switchView("renamer");
});

// --- Optional tool detection hint ---
async function refreshToolHint() {
  try {
    const tools = await window.Bridge.call("checkTools");
    const extras = [];
    extras.push(tools && tools.calibre ? "Calibre: found" : "Calibre: not found");
    extras.push(tools && tools.djvulibre ? "DjVuLibre: found" : "DjVuLibre: not found (needed to read DjVu)");
    extras.push(tools && tools.pdf2djvu ? "pdf2djvu: found" : "pdf2djvu: not found (needed to write DjVu)");
    toolsHint.textContent = extras.join(" • ");
  } catch {
    toolsHint.textContent = "";
  }
}

// --- Queue building ---
function buildQueue() {
  const hasSource = sourceFiles.length > 0;
  configCard.classList.toggle("disabled", !hasSource);
  for (const el of [targetSelect, filterSelect, conflictSelect]) el.disabled = !hasSource;

  if (!hasSource) {
    queue = [];
    renderQueue();
    return;
  }

  queue = generateConversionPreview(sourceFiles, {
    targetFormat: targetSelect.value,
    sourceFormatFilter: filterSelect.value,
    conflictAction: conflictSelect.value,
    outputDirectory,
    existingTargetFiles: existingPaths
  });
  renderQueue();
}

const STATUS_LABELS = {
  ready: "Ready",
  same_format: "Already target format",
  skipped: "Will skip (exists)",
  conflict: "Conflict",
  done: "Converted",
  failed: "Failed"
};

function renderQueue() {
  tbody.replaceChildren();
  const hasItems = queue.length > 0;
  countBadge.textContent = `${queue.length} File${queue.length === 1 ? "" : "s"}`;
  emptyState.classList.toggle("hidden", hasItems);
  tableWrapper.classList.toggle("hidden", !hasItems);
  footer.classList.toggle("hidden", !hasItems);

  if (!hasItems) {
    const msg = emptyState.querySelector("p");
    msg.textContent = sourceFiles.length > 0
      ? "No supported documents match the current source filter."
      : "Select documents or a folder to build a conversion queue.";
    return;
  }

  for (const item of queue) {
    const tr = document.createElement("tr");
    const state = item.result || item.status;
    tr.className = state === "conflict" || state === "failed" ? "tr-conflict"
      : state === "ready" || state === "done" ? "tr-modified" : "tr-unchanged";

    const cells = [
      item.originalName,
      item.sourceFormat.toUpperCase(),
      formatBytes(item.size),
      item.targetName,
      STATUS_LABELS[state] || state
    ];
    cells.forEach((text, i) => {
      const td = document.createElement("td");
      td.textContent = text;
      if (i === 0) td.title = item.originalName;
      if (i === 3) td.className = "destination-name-cell";
      if (i === 4) td.title = item.errorMessage || item.conflictReason || "";
      tr.appendChild(td);
    });
    tbody.appendChild(tr);
  }

  const ready = queue.filter((q) => q.willConvert).length;
  const conflicts = queue.filter((q) => q.conflict).length;
  if (conflicts > 0) {
    summary.textContent = `${conflicts} output conflict${conflicts === 1 ? "" : "s"} detected`;
    summary.style.color = "var(--error-red)";
  } else if (ready === 0) {
    summary.textContent = "Nothing to convert";
    summary.style.color = "var(--text-secondary)";
  } else {
    summary.textContent = `Ready to convert ${ready} file${ready === 1 ? "" : "s"}`;
    summary.style.color = "var(--accent-cyan)";
  }
  btnRun.disabled = busy || ready === 0 || conflicts > 0;
}

// --- Existing destination listing (for collision detection) ---
async function refreshExistingPaths() {
  const dirs = new Set();
  if (outputDirectory) {
    dirs.add(outputDirectory);
  } else {
    for (const f of sourceFiles) dirs.add(f.directory);
  }
  const paths = [];
  await Promise.all([...dirs].map(async (dir) => {
    try {
      const entries = await window.Bridge.call("readDirectory", { path: dir });
      for (const e of entries || []) paths.push(`${dir}/${e.name}`);
    } catch {
      // Directory may not exist yet (e.g. new output folder); treat as empty.
    }
  }));
  existingPaths = paths;
}

async function setSources(files, label) {
  sourceFiles = files;
  sourceLabel.value = label;
  await refreshExistingPaths();
  buildQueue();
}

// --- Selection handlers ---
btnFiles.addEventListener("click", async () => {
  try {
    const files = await window.Bridge.call("selectFiles");
    const docs = (files || []).filter((f) => isSupportedDocument(f.name, false));
    const skipped = (files || []).length - docs.length;
    if (skipped > 0) {
      showToast("Unsupported Files Ignored", `${skipped} file${skipped === 1 ? "" : "s"} skipped (unsupported format).`, "info");
    }
    await setSources(docs, `${docs.length} file${docs.length === 1 ? "" : "s"} selected`);
  } catch (error) {
    if (error.message !== "Cancelled") showToast("Selection Error", error.message, "error");
  }
});

btnFolder.addEventListener("click", async () => {
  try {
    const dir = await window.Bridge.call("selectDirectory");
    const entries = await window.Bridge.call("readDirectory", { path: dir });
    const docs = (entries || [])
      .filter((e) => isSupportedDocument(e.name, e.isDirectory))
      .map((e) => ({ name: e.name, size: e.size, directory: dir, path: `${dir}/${e.name}` }));
    await setSources(docs, dir);
  } catch (error) {
    if (error.message !== "Cancelled") showToast("Selection Error", error.message, "error");
  }
});

btnOutput.addEventListener("click", async () => {
  try {
    const dir = await window.Bridge.call("selectDirectory");
    outputDirectory = dir;
    outputLabel.value = dir;
    await refreshExistingPaths();
    buildQueue();
  } catch (error) {
    if (error.message !== "Cancelled") showToast("Selection Error", error.message, "error");
  }
});

btnOutputReset.addEventListener("click", async () => {
  outputDirectory = null;
  outputLabel.value = "Same folder as source";
  await refreshExistingPaths();
  buildQueue();
});

for (const el of [targetSelect, filterSelect, conflictSelect]) {
  el.addEventListener("change", buildQueue);
}

// --- Execution ---
btnRun.addEventListener("click", async () => {
  const toConvert = queue.filter((q) => q.willConvert);
  if (busy || toConvert.length === 0) return;

  busy = true;
  btnRun.disabled = true;
  btnRun.textContent = "Converting...";

  try {
    const data = await window.Bridge.call("executeConversion", {
      items: toConvert.map((q) => ({
        sourcePath: q.sourcePath,
        targetPath: q.targetPath,
        targetFormat: q.targetFormat
      }))
    });

    const byPath = new Map((data.results || []).map((r) => [r.sourcePath, r]));
    let failed = 0;
    for (const item of queue) {
      const r = byPath.get(item.sourcePath);
      if (!r) continue;
      item.result = r.ok ? "done" : "failed";
      if (!r.ok) {
        failed++;
        item.errorMessage = r.error;
      }
    }

    if (failed === 0) {
      showToast("Conversion Complete", `Converted ${data.convertedCount} file${data.convertedCount === 1 ? "" : "s"}.`, "success");
    } else {
      showToast("Conversion Finished With Errors", `${data.convertedCount} succeeded, ${failed} failed. Hover over a status for details.`, "error");
    }
    btnReveal.classList.remove("hidden");
    await refreshExistingPaths();
    renderQueue();
    summary.textContent = `${data.convertedCount} converted, ${failed} failed`;
  } catch (error) {
    showToast("Conversion Error", error.message, "error");
  } finally {
    busy = false;
    btnRun.textContent = "Convert Documents";
    btnRun.disabled = true; // queue is stale until user changes selection/options
  }
});

btnReveal.addEventListener("click", async () => {
  const dir = outputDirectory || (sourceFiles[0] && sourceFiles[0].directory);
  if (dir) await window.Bridge.call("openInFinder", { path: dir });
});

// Keep the format list in sync with the select options (guards against drift).
for (const opt of targetSelect.options) {
  if (!SUPPORTED_FORMATS.some((f) => f.id === opt.value)) {
    console.warn(`Target option '${opt.value}' is not a supported format`);
  }
}
