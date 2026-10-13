import { generatePreview } from "./renamer.js";

// --- IPC Bridge Setup ---
window.Bridge = {
  callbacks: {},
  counter: 0,
  
  call(action, data = {}) {
    return new Promise((resolve, reject) => {
      // Generate a unique callback ID
      const callbackId = `cb_${this.counter++}`;
      this.callbacks[callbackId] = { resolve, reject };
      
      const payload = {
        action,
        callbackId,
        ...data
      };
      
      // Post message to native Swift app wrapper
      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.bridge) {
        window.webkit.messageHandlers.bridge.postMessage(payload);
      } else {
        // Fallback for debugging in regular browser environments
        console.warn(`Native bridge not available. Action: ${action}`, payload);
        setTimeout(() => {
          if (action === "selectDirectory") {
            resolve("/mock/user/directory");
          } else if (action === "readDirectory") {
            resolve([
              { name: "beach_photo.jpg", size: 1024000, isDirectory: false },
              { name: "family_portrait.png", size: 2048500, isDirectory: false },
              { name: "old_logs.txt", size: 450, isDirectory: false },
              { name: "documents_folder", size: 0, isDirectory: true }
            ]);
          } else if (action === "executeRename") {
            resolve({ renamedCount: data.renames.length });
          } else if (action === "selectFiles") {
            resolve([{ name: "book.epub", path: "/mock/book.epub", directory: "/mock", size: 150000, isDirectory: false }]);
          } else if (action === "checkTools") {
            resolve({ calibre: false, djvulibre: false, pdf2djvu: false });
          } else if (action === "executeConversion") {
            resolve({
              convertedCount: data.items.length,
              results: data.items.map(i => ({ sourcePath: i.sourcePath, ok: true }))
            });
          } else {
            resolve(true);
          }
        }, 800);
      }
    });
  },
  
  resolve(callbackId, response) {
    const cb = this.callbacks[callbackId];
    if (cb) {
      delete this.callbacks[callbackId];
      if (response.error) {
        cb.reject(new Error(response.error));
      } else {
        cb.resolve(response.data);
      }
    }
  }
};

// --- App State ---
let selectedDirectoryPath = null;
let directoryFiles = [];
let previewItems = [];

// --- UI Element Selectors ---
const btnBrowse = document.getElementById("btn-browse");
const btnRename = document.getElementById("btn-rename");
const btnReveal = document.getElementById("btn-reveal");
const directoryPathInput = document.getElementById("directory-path");
const configCard = document.getElementById("config-card");
const prefixInput = document.getElementById("prefix-input");
const formatSelect = document.getElementById("format-select");
const indexInput = document.getElementById("index-input");
const paddingInput = document.getElementById("padding-input");
const fileCountBadge = document.getElementById("file-count");
const emptyState = document.getElementById("empty-state");
const tableWrapper = document.getElementById("table-wrapper");
const previewTbody = document.getElementById("preview-tbody");
const executionFooter = document.getElementById("execution-footer");
const statsSummary = document.getElementById("stats-summary");
const alertContainer = document.getElementById("alert-container");

// --- Utility: Format File Size ---
export function formatBytes(bytes) {
  if (bytes === 0) return "0 B";
  const k = 1024;
  const sizes = ["B", "KB", "MB", "GB"];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + " " + sizes[i];
}

// --- Toast Notifications System ---
export function showToast(title, message, type = "info") {
  const toast = document.createElement("div");
  toast.className = `alert-toast ${type}`;
  
  let iconSvg = "";
  if (type === "success") {
    iconSvg = `<svg class="toast-icon" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" /></svg>`;
  } else if (type === "error") {
    iconSvg = `<svg class="toast-icon" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" /></svg>`;
  } else {
    iconSvg = `<svg class="toast-icon" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" /></svg>`;
  }
  
  toast.innerHTML = `
    ${iconSvg}
    <div class="toast-content">
      <div class="toast-title">${title}</div>
      <div class="toast-msg">${message}</div>
    </div>
  `;
  
  alertContainer.appendChild(toast);
  
  // Auto-remove toast after 4s
  setTimeout(() => {
    toast.style.animation = "toastIn 0.3s cubic-bezier(0.16, 1, 0.3, 1) reverse forwards";
    setTimeout(() => toast.remove(), 300);
  }, 4000);
}

// --- Action: Load Directory File List ---
async function loadDirectoryContents(path) {
  try {
    const files = await window.Bridge.call("readDirectory", { path });
    // Sort files to keep folder list tidy
    directoryFiles = files || [];
    fileCountBadge.textContent = `${directoryFiles.length} File${directoryFiles.length === 1 ? "" : "s"}`;
    
    if (directoryFiles.length === 0) {
      showEmptyState("This folder contains no files to rename.");
    } else {
      emptyState.classList.add("hidden");
      tableWrapper.classList.remove("hidden");
      executionFooter.classList.remove("hidden");
      btnReveal.classList.remove("hidden");
      
      // Enable settings cards and input elements
      configCard.classList.remove("disabled");
      prefixInput.removeAttribute("disabled");
      formatSelect.removeAttribute("disabled");
      indexInput.removeAttribute("disabled");
      paddingInput.removeAttribute("disabled");
      
      updatePreview();
    }
  } catch (error) {
    showToast("Error Reading Folder", error.message, "error");
    showEmptyState(`Could not load files: ${error.message}`);
  }
}

function showEmptyState(msg) {
  emptyState.innerHTML = `
    <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round">
      <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/>
      <polyline points="14 2 14 8 20 8"/>
    </svg>
    <p>${msg}</p>
  `;
  emptyState.classList.remove("hidden");
  tableWrapper.classList.add("hidden");
  executionFooter.classList.add("hidden");
  configCard.classList.add("disabled");
  prefixInput.setAttribute("disabled", "true");
  formatSelect.setAttribute("disabled", "true");
  indexInput.setAttribute("disabled", "true");
  paddingInput.setAttribute("disabled", "true");
  fileCountBadge.textContent = "0 Files";
}

// --- Action: Calculate & Render Renaming Preview ---
function updatePreview() {
  if (directoryFiles.length === 0) return;
  
  const options = {
    prefix: prefixInput.value.trim(),
    format: formatSelect.value,
    startIndex: parseInt(indexInput.value) || 1,
    padding: parseInt(paddingInput.value) || 3
  };
  
  try {
    prefixInput.classList.remove("shake");
    previewItems = generatePreview(directoryFiles, options);
    renderPreviewTable(previewItems);
    
    // Check conflicts count
    const conflicts = previewItems.filter(item => item.conflict);
    const unmodified = previewItems.filter(item => item.isUnchanged);
    const modifiedCount = previewItems.length - unmodified.length;
    
    if (conflicts.length > 0) {
      statsSummary.textContent = `${conflicts.length} name conflict${conflicts.length === 1 ? "" : "s"} detected`;
      statsSummary.style.color = "var(--error-red)";
      btnRename.setAttribute("disabled", "true");
    } else if (modifiedCount === 0) {
      statsSummary.textContent = "No names will be changed";
      statsSummary.style.color = "var(--text-secondary)";
      btnRename.setAttribute("disabled", "true");
    } else {
      statsSummary.textContent = `Ready to rename ${modifiedCount} file${modifiedCount === 1 ? "" : "s"}`;
      statsSummary.style.color = "var(--accent-cyan)";
      btnRename.removeAttribute("disabled");
    }
  } catch (error) {
    // Show validation error (illegal characters)
    statsSummary.textContent = error.message;
    statsSummary.style.color = "var(--error-red)";
    btnRename.setAttribute("disabled", "true");
    prefixInput.classList.add("shake");
    showToast("Invalid Prefix", error.message, "error");
  }
}

function renderPreviewTable(items) {
  previewTbody.innerHTML = "";
  
  for (const item of items) {
    const tr = document.createElement("tr");
    
    if (item.conflict) {
      tr.className = "tr-conflict";
    } else if (item.isUnchanged) {
      tr.className = "tr-unchanged";
    } else {
      tr.className = "tr-modified";
    }
    
    // File/Folder SVG icon
    const iconSvg = item.isDirectory 
      ? `<svg class="file-icon folder" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M3 7v10a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-6l-2-2H5a2 2 0 00-2 2z" /></svg>`
      : `<svg class="file-icon file" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M7 21h10a2 2 0 002-2V9.414a1 1 0 00-.293-.707l-5.414-5.414A1 1 0 0012.586 3H7a2 2 0 00-2 2v14a2 2 0 002 2z" /></svg>`;
    
    const sizeDisplay = item.isDirectory ? "--" : formatBytes(item.size);
    const typeLabel = item.isDirectory ? "Folder" : (item.originalName.split(".").pop() || "File").toUpperCase();
    
    let destContent = "";
    if (item.isUnchanged) {
      destContent = `<span class="destination-name-cell">${item.newName}</span>`;
    } else if (item.conflict) {
      destContent = `
        <span class="destination-name-cell">
          ${item.newName}
          <span class="conflict-badge" title="${item.conflictReason}">!</span>
        </span>`;
    } else {
      destContent = `
        <span class="destination-name-cell">
          ${item.newName}
        </span>`;
    }
    
    tr.innerHTML = `
      <td>
        <div class="file-name-cell" title="${item.originalName}">
          ${iconSvg}
          <span>${item.originalName}</span>
        </div>
      </td>
      <td><span class="file-type-badge">${typeLabel}</span></td>
      <td class="file-size-cell">${sizeDisplay}</td>
      <td>${destContent}</td>
    `;
    
    previewTbody.appendChild(tr);
  }
}

// --- Action: Execute Renaming on Disk ---
async function runRenaming() {
  if (!selectedDirectoryPath || previewItems.length === 0) return;
  
  const toRename = previewItems.filter(item => !item.isUnchanged && !item.conflict);
  if (toRename.length === 0) return;
  
  const payload = toRename.map(item => ({
    oldName: item.originalName,
    newName: item.newName
  }));
  
  btnRename.setAttribute("disabled", "true");
  btnRename.innerHTML = `
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" style="animation: spin 1s linear infinite">
      <path d="M4 4v5h.582m15.356 2A8.001 8.001 0 1 1 21.753 9H17" />
    </svg>
    Renaming...
  `;
  
  try {
    const result = await window.Bridge.call("executeRename", {
      directory: selectedDirectoryPath,
      renames: payload
    });
    
    showToast(
      "Renaming Complete", 
      `Successfully renamed ${result.renamedCount} of ${payload.length} files.`,
      "success"
    );
    
    // Reset prefix input for safety, keeping directory loaded
    prefixInput.value = "";
    
    // Reload folder contents to show the fresh file names!
    await loadDirectoryContents(selectedDirectoryPath);
  } catch (error) {
    showToast("Renaming Error", error.message, "error");
    // Reload directory in case some items succeeded before the failure
    await loadDirectoryContents(selectedDirectoryPath);
  } finally {
    btnRename.innerHTML = `
      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round">
        <polyline points="20 6 9 17 4 12"/>
      </svg>
      Rename Files
    `;
  }
}

// --- Event Listeners Bindings ---

// Folder Selection
btnBrowse.addEventListener("click", async () => {
  try {
    const path = await window.Bridge.call("selectDirectory");
    selectedDirectoryPath = path;
    directoryPathInput.value = path;
    
    showToast("Folder Selected", `Loaded workspace path: ${path}`, "info");
    await loadDirectoryContents(path);
  } catch (error) {
    if (error.message !== "Cancelled") {
      showToast("Directory Selection Error", error.message, "error");
    }
  }
});

// Settings Changes
prefixInput.addEventListener("input", updatePreview);
indexInput.addEventListener("input", updatePreview);
paddingInput.addEventListener("input", updatePreview);

formatSelect.addEventListener("change", () => {
  const isOriginal = formatSelect.value === "prefix_original";
  document.querySelectorAll(".number-option").forEach(el => {
    if (isOriginal) {
      el.classList.add("hidden");
    } else {
      el.classList.remove("hidden");
    }
  });
  updatePreview();
});

// Run execution
btnRename.addEventListener("click", runRenaming);

// Open Finder
btnReveal.addEventListener("click", async () => {
  if (selectedDirectoryPath) {
    await window.Bridge.call("openInFinder", { path: selectedDirectoryPath });
  }
});

// CSS Spinning Keyframes for Loading state
const styleSheet = document.createElement("style");
styleSheet.innerText = `
  @keyframes spin {
    from { transform: rotate(0deg); }
    to { transform: rotate(360deg); }
  }
`;
document.head.appendChild(styleSheet);
