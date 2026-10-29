import { showToast } from "./renderer.js";
import { switchAppView } from "./converter-ui.js";
import {
  extractPrimaryContent,
  sanitizeFileName,
  buildPrintableHtml
} from "./web-extractor.js";

// --- DOM Selectors ---
const $ = (id) => document.getElementById(id);

const navWebToPdf = $("nav-web-to-pdf");
const viewWebToPdf = $("view-web-to-pdf");
const urlInput = $("web-url-input");
const btnPaste = $("web-btn-paste");
const btnFetch = $("web-btn-fetch");
const modeSelect = $("web-mode");
const paperSizeSelect = $("web-paper-size");
const configCard = $("web-config-card");
const previewCard = $("web-preview-card");
const emptyState = $("web-empty-state");
const previewContent = $("web-preview-content");
const articleTitleEl = $("web-article-title");
const articleMetaEl = $("web-article-meta");
const articleLeadImgEl = $("web-article-lead-img");
const articleBodyEl = $("web-article-body");
const executionFooter = $("web-footer");
const summaryEl = $("web-summary");
const btnSave = $("web-btn-save");
const btnReveal = $("web-btn-reveal");

// --- Component State ---
let currentUrl = "";
let rawHtml = "";
let currentArticle = null;
let savedPdfPath = null;
let busy = false;

// --- Sidebar Navigation Hook ---
if (navWebToPdf) {
  navWebToPdf.addEventListener("click", (e) => {
    e.preventDefault();
    if (viewWebToPdf && viewWebToPdf.classList.contains("hidden")) {
      switchAppView("web-to-pdf");
    }
  });
}

// --- Fetch & Extraction ---
async function fetchAndExtract() {
  let url = (urlInput.value || "").trim();
  if (!url) {
    showToast("Invalid URL", "Please enter a webpage address to download.", "error");
    urlInput.focus();
    return;
  }

  // Prepend https:// if protocol omitted
  if (!/^https?:\/\//i.test(url)) {
    url = `https://${url}`;
    urlInput.value = url;
  }

  setBusy(true, "Fetching...");
  btnReveal.classList.add("hidden");
  savedPdfPath = null;

  try {
    const response = await window.Bridge.call("fetchWebpage", { url });
    rawHtml = response.html;
    currentUrl = response.url || url;

    processExtractedContent();
    showToast("Webpage Loaded", `Extracted content from ${new URL(currentUrl).hostname}`, "success");
  } catch (error) {
    showToast("Fetch Error", error.message || "Failed to download webpage", "error");
  } finally {
    setBusy(false);
  }
}

function processExtractedContent() {
  if (!rawHtml) return;

  const mode = modeSelect.value;
  currentArticle = extractPrimaryContent(rawHtml, currentUrl, { mode });

  renderArticlePreview(currentArticle);
}

function renderArticlePreview(article) {
  if (!article) return;

  emptyState.classList.add("hidden");
  previewContent.classList.remove("hidden");
  configCard.classList.remove("disabled");
  modeSelect.disabled = false;
  paperSizeSelect.disabled = false;
  executionFooter.classList.remove("hidden");
  btnSave.disabled = false;

  // Title
  articleTitleEl.textContent = article.title || "Untitled Webpage";

  // Meta pills
  const metaParts = [];
  if (article.siteName) metaParts.push(`<span class="meta-pill meta-site">${escapeHtml(article.siteName)}</span>`);
  if (article.byline) metaParts.push(`<span class="meta-pill meta-author">By ${escapeHtml(article.byline)}</span>`);
  if (article.publishedTime) {
    const d = new Date(article.publishedTime);
    const dateFormatted = isNaN(d.getTime()) ? article.publishedTime : d.toLocaleDateString(undefined, { year: "numeric", month: "short", day: "numeric" });
    metaParts.push(`<span class="meta-pill meta-date">${escapeHtml(dateFormatted)}</span>`);
  }
  metaParts.push(`<span class="meta-pill meta-stats">${article.readingTimeMinutes} min read • ${article.wordCount} words</span>`);
  articleMetaEl.innerHTML = metaParts.join("");

  // Lead image
  if (article.leadImage) {
    articleLeadImgEl.innerHTML = `<img src="${escapeHtml(article.leadImage)}" alt="Lead article image" onerror="this.parentElement.style.display='none'">`;
    articleLeadImgEl.style.display = "block";
  } else {
    articleLeadImgEl.innerHTML = "";
    articleLeadImgEl.style.display = "none";
  }

  // Article body
  articleBodyEl.innerHTML = article.contentHtml || "<p>No primary text detected.</p>";

  // Footer summary
  summaryEl.textContent = `Ready to save: ${article.wordCount} words (${article.readingTimeMinutes} min read)`;
}

// --- Save as PDF Action ---
async function saveWebpageAsPDF() {
  if (!currentArticle) return;

  const defaultName = sanitizeFileName(currentArticle.title, "pdf");

  try {
    // 1. Prompt macOS Save File Picker
    const targetPath = await window.Bridge.call("saveFilePicker", { defaultName });
    if (!targetPath) return;

    setSaving(true);

    // 2. Build print-ready HTML
    const paperSize = paperSizeSelect.value;
    const printableHtml = buildPrintableHtml(currentArticle, { paperSize });

    // 3. Request native WebKit PDF generation
    const result = await window.Bridge.call("generateWebpagePDF", {
      html: printableHtml,
      targetPath,
      baseURL: currentArticle.url
    });

    savedPdfPath = result.path || targetPath;
    const fileName = savedPdfPath.split("/").pop();

    showToast("PDF Created", `Saved "${fileName}" successfully!`, "success");
    btnReveal.classList.remove("hidden");
    summaryEl.textContent = `Saved: ${fileName}`;
  } catch (error) {
    if (error.message !== "Cancelled") {
      showToast("PDF Generation Failed", error.message || "Failed to create PDF", "error");
    }
  } finally {
    setSaving(false);
  }
}

// --- Reveal in Finder ---
async function revealInFinder() {
  if (savedPdfPath) {
    await window.Bridge.call("openInFinder", { path: savedPdfPath });
  }
}

// --- Helper Functions ---
function setBusy(isBusy, text = "Fetch") {
  busy = isBusy;
  btnFetch.disabled = isBusy;
  urlInput.disabled = isBusy;
  if (isBusy) {
    btnFetch.innerHTML = `
      <svg class="spin-icon" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <path d="M21 12a9 9 0 1 1-6.219-8.56"/>
      </svg>
      ${text}
    `;
  } else {
    btnFetch.innerHTML = `
      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round">
        <polyline points="8 17 12 21 16 17"/>
        <line x1="12" y1="12" x2="12" y2="21"/>
        <path d="M20.88 18.09A5 5 0 0 0 18 9h-1.26A8 8 0 1 0 3 16.29"/>
      </svg>
      Fetch & Preview
    `;
  }
}

function setSaving(isSaving) {
  btnSave.disabled = isSaving;
  if (isSaving) {
    btnSave.innerHTML = `
      <svg class="spin-icon" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <path d="M21 12a9 9 0 1 1-6.219-8.56"/>
      </svg>
      Saving PDF...
    `;
  } else {
    btnSave.innerHTML = `
      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round">
        <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/>
        <polyline points="14 2 14 8 20 8"/>
        <line x1="12" y1="18" x2="12" y2="12"/>
        <line x1="9" y1="15" x2="15" y2="15"/>
      </svg>
      Save as PDF...
    `;
  }
}

function escapeHtml(str) {
  if (!str) return "";
  return String(str)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

// --- Event Listeners ---
if (btnPaste) {
  btnPaste.addEventListener("click", async () => {
    try {
      let text = "";
      if (window.Bridge) {
        try {
          text = await window.Bridge.call("readClipboard");
        } catch {
          text = "";
        }
      }
      if (!text && navigator.clipboard && navigator.clipboard.readText) {
        try {
          text = await navigator.clipboard.readText();
        } catch {
          text = "";
        }
      }
      if (text && typeof text === "string" && text.trim()) {
        urlInput.value = text.trim();
        urlInput.focus();
        showToast("Pasted from Clipboard", text.trim().substring(0, 60), "info");
      } else {
        showToast("Clipboard Empty", "No text found in clipboard to paste.", "warning");
      }
    } catch (error) {
      showToast("Paste Error", error.message || "Could not read clipboard", "error");
    }
  });
}

btnFetch.addEventListener("click", fetchAndExtract);
urlInput.addEventListener("keydown", (e) => {
  if (e.key === "Enter") {
    e.preventDefault();
    fetchAndExtract();
  }
});

modeSelect.addEventListener("change", processExtractedContent);
btnSave.addEventListener("click", saveWebpageAsPDF);
btnReveal.addEventListener("click", revealInFinder);
