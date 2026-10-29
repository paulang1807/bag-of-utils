/**
 * Web Article Content Extractor & PDF Formatter
 * Zero-dependency, standards-compliant extraction of primary article content
 * from web pages for clean rendering and PDF export.
 */

// Characters disallowed in macOS filenames: / : and control chars
const ILLEGAL_FILENAME_REGEX = /[/\\:?*"<>|\x00-\x1f\x7f]/g;

/**
 * Sanitizes a title string into a safe, standard macOS filename.
 * @param {string} title
 * @param {string} [ext="pdf"]
 * @returns {string}
 */
export function sanitizeFileName(title, ext = "pdf") {
  if (!title || typeof title !== "string") {
    return `webpage.${ext}`;
  }
  
  let clean = title
    .replace(ILLEGAL_FILENAME_REGEX, " ")
    .replace(/\s+/g, " ")
    .trim();

  // Strip trailing dots or spaces
  clean = clean.replace(/[. ]+$/, "");

  // Truncate to maximum 100 characters to prevent filesystem errors
  if (clean.length > 100) {
    clean = clean.substring(0, 100).trim();
  }

  if (!clean) {
    clean = "webpage";
  }

  const cleanExt = ext.replace(/^\.+/, "");
  return `${clean}.${cleanExt}`;
}

/**
 * Calculates reading time and word count statistics.
 * @param {string} text
 * @returns {{ wordCount: number, readingTimeMinutes: number }}
 */
export function estimateReadingStats(text) {
  if (!text || typeof text !== "string") {
    return { wordCount: 0, readingTimeMinutes: 1 };
  }
  const words = text.trim().split(/\s+/).filter(Boolean);
  const wordCount = words.length;
  const readingTimeMinutes = Math.max(1, Math.ceil(wordCount / 200));
  return { wordCount, readingTimeMinutes };
}

/**
 * Resolves a relative URL against a base URL safely.
 * @param {string} relativeUrl
 * @param {string} baseUrl
 * @returns {string}
 */
export function resolveUrl(relativeUrl, baseUrl) {
  if (!relativeUrl || typeof relativeUrl !== "string") return "";
  const trimmed = relativeUrl.trim();
  if (!trimmed || trimmed.startsWith("data:") || trimmed.startsWith("blob:")) return trimmed;
  if (!baseUrl) return trimmed;
  try {
    return new URL(trimmed, baseUrl).href;
  } catch {
    return trimmed;
  }
}

/**
 * Extract domain/host name from a URL.
 * @param {string} url
 * @returns {string}
 */
export function getDomainFromUrl(url) {
  if (!url) return "";
  try {
    const parsed = new URL(url);
    return parsed.hostname.replace(/^www\./, "");
  } catch {
    return "";
  }
}

/**
 * Extracts metadata from HTML string via regex for speed and cross-environment reliability.
 * @param {string} html
 * @param {string} [url=""]
 * @returns {{ title: string, byline: string, publishedTime: string, siteName: string, leadImage: string }}
 */
export function extractMetadata(html, url = "") {
  if (!html || typeof html !== "string") {
    return { title: "Untitled Page", byline: "", publishedTime: "", siteName: getDomainFromUrl(url), leadImage: "" };
  }

  const getMeta = (names) => {
    for (const name of names) {
      const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      // <meta (property|name)="NAME" content="VALUE"> or <meta content="VALUE" (property|name)="NAME">
      const r1 = new RegExp(`<meta[^>]+(?:property|name)=["']${escaped}["'][^>]+content=["']([^"']+)["']`, "i");
      const m1 = r1.exec(html);
      if (m1 && m1[1]) return decodeHTMLEntities(m1[1].trim());

      const r2 = new RegExp(`<meta[^>]+content=["']([^"']+)["'][^>]+(?:property|name)=["']${escaped}["']`, "i");
      const m2 = r2.exec(html);
      if (m2 && m2[1]) return decodeHTMLEntities(m2[1].trim());
    }
    return "";
  };

  // Title extraction: og:title -> twitter:title -> <title> -> <h1>
  let title = getMeta(["og:title", "twitter:title", "title"]);
  if (!title) {
    const titleTagMatch = /<title[^>]*>([^<]+)<\/title>/i.exec(html);
    if (titleTagMatch && titleTagMatch[1]) {
      title = decodeHTMLEntities(titleTagMatch[1].trim());
    }
  }
  if (!title) {
    const h1Match = /<h1[^>]*>([^<]+)<\/h1>/i.exec(html);
    if (h1Match && h1Match[1]) {
      title = decodeHTMLEntities(h1Match[1].trim());
    }
  }
  if (!title) {
    title = "Untitled Webpage";
  }

  // Byline / Author
  let byline = getMeta(["author", "article:author", "twitter:creator", "byl", "sailthru.author"]);
  if (!byline) {
    const authorMatch = /<[a-z0-9]+[^>]+(?:class|rel)=["'][^"']*\b(?:author|byline|creator)\b[^"']*["'][^>]*>([^<]+)<\/[a-z0-9]+>/i.exec(html);
    if (authorMatch && authorMatch[1]) {
      byline = decodeHTMLEntities(authorMatch[1].trim()).replace(/^by\s+/i, "");
    }
  }

  // Published Time
  let publishedTime = getMeta(["article:published_time", "og:article:published_time", "date", "pubdate", "sailthru.date"]);
  if (!publishedTime) {
    const timeMatch = /<time[^>]+datetime=["']([^"']+)["']/i.exec(html);
    if (timeMatch && timeMatch[1]) {
      publishedTime = timeMatch[1].trim();
    }
  }

  // Site name
  let siteName = getMeta(["og:site_name", "application-name", "publisher"]);
  if (!siteName) {
    siteName = getDomainFromUrl(url);
  }

  // Lead image
  let leadImage = getMeta(["og:image", "twitter:image", "image"]);
  if (leadImage && url) {
    leadImage = resolveUrl(leadImage, url);
  }

  return { title, byline, publishedTime, siteName, leadImage };
}

/**
 * Decodes basic HTML entities.
 * @param {string} text
 * @returns {string}
 */
export function decodeHTMLEntities(text) {
  if (!text) return "";
  return text
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&nbsp;/g, " ")
    .replace(/&#(\d+);/g, (_, code) => String.fromCharCode(code))
    .replace(/&#x([0-9a-fA-F]+);/g, (_, hex) => String.fromCharCode(parseInt(hex, 16)));
}

/**
 * Lightweight Mini-DOM Node for zero-dependency parsing and extraction.
 */
class MiniNode {
  constructor(tag, attrs = {}) {
    this.tagName = tag ? tag.toUpperCase() : "#TEXT";
    this.nodeType = tag ? 1 : 3;
    this.attrs = attrs;
    this.children = [];
    this.parentNode = null;
    this.textValue = "";
  }

  get textContent() {
    if (this.nodeType === 3) return this.textValue;
    return this.children.map(c => c.textContent).join("");
  }

  set textContent(val) {
    if (this.nodeType === 3) {
      this.textValue = val;
    } else {
      this.children = [];
      const textNode = new MiniNode(null);
      textNode.textValue = val;
      textNode.parentNode = this;
      this.children.push(textNode);
    }
  }

  getAttribute(name) {
    return this.attrs[name.toLowerCase()] ?? null;
  }

  setAttribute(name, val) {
    this.attrs[name.toLowerCase()] = String(val);
  }

  removeAttribute(name) {
    delete this.attrs[name.toLowerCase()];
  }

  appendChild(child) {
    child.parentNode = this;
    this.children.push(child);
  }

  remove() {
    if (this.parentNode) {
      const idx = this.parentNode.children.indexOf(this);
      if (idx !== -1) {
        this.parentNode.children.splice(idx, 1);
      }
      this.parentNode = null;
    }
  }

  getElementsByTagName(tagName) {
    const upper = tagName.toUpperCase();
    const result = [];
    const traverse = (node) => {
      for (const child of node.children) {
        if (child.nodeType === 1) {
          if (upper === "*" || child.tagName === upper) {
            result.push(child);
          }
          traverse(child);
        }
      }
    };
    traverse(this);
    return result;
  }

  toHTML() {
    if (this.nodeType === 3) {
      return this.textValue
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;");
    }
    const tag = this.tagName.toLowerCase();
    const attrStrings = Object.entries(this.attrs)
      .map(([k, v]) => ` ${k}="${String(v).replace(/"/g, '&quot;')}"`)
      .join("");

    const isVoid = ["img", "br", "hr", "input", "meta", "link"].includes(tag);
    if (isVoid) {
      return `<${tag}${attrStrings}>`;
    }
    const inner = this.children.map(c => c.toHTML()).join("");
    return `<${tag}${attrStrings}>${inner}</${tag}>`;
  }
}

/**
 * Parses raw HTML string into a MiniNode DOM tree.
 * @param {string} html
 * @returns {MiniNode} Root document node
 */
export function parseHTMLToTree(html) {
  const root = new MiniNode("root");
  let current = root;

  // Strip comments
  const cleanHtml = html.replace(/<!--[\s\S]*?-->/g, "");

  const tagRegex = /<(\/)?([a-zA-Z0-9\-]+)([^>]*)>|([^<]+)/g;
  let match;

  const voidElements = new Set(["img", "br", "hr", "input", "meta", "link", "area", "base", "col", "embed", "param", "source", "track", "wbr"]);

  while ((match = tagRegex.exec(cleanHtml)) !== null) {
    if (match[4]) {
      // Text node
      const text = decodeHTMLEntities(match[4]);
      if (text) {
        const textNode = new MiniNode(null);
        textNode.textValue = text;
        current.appendChild(textNode);
      }
    } else {
      const isClosing = Boolean(match[1]);
      const tagName = match[2].toLowerCase();
      const rawAttrs = match[3] || "";

      if (isClosing) {
        // Walk up to matching opening tag
        let ancestor = current;
        while (ancestor && ancestor !== root) {
          if (ancestor.tagName.toLowerCase() === tagName) {
            current = ancestor.parentNode || root;
            break;
          }
          ancestor = ancestor.parentNode;
        }
      } else {
        // Opening tag
        const attrs = {};
        const attrRegex = /([a-zA-Z0-9\-:_]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+)))?/g;
        let attrMatch;
        while ((attrMatch = attrRegex.exec(rawAttrs)) !== null) {
          const key = attrMatch[1].toLowerCase();
          const val = attrMatch[2] ?? attrMatch[3] ?? attrMatch[4] ?? "";
          attrs[key] = decodeHTMLEntities(val);
        }

        const el = new MiniNode(tagName, attrs);
        current.appendChild(el);

        const isSelfClosing = rawAttrs.trim().endsWith("/") || voidElements.has(tagName);
        if (!isSelfClosing) {
          current = el;
        }
      }
    }
  }

  return root;
}

/**
 * Elements typically considered junk or distracting in a reader article.
 */
const JUNK_TAGS = new Set([
  "SCRIPT", "STYLE", "NOSCRIPT", "IFRAME", "SVG", "FORM", "BUTTON",
  "INPUT", "SELECT", "TEXTAREA", "CANVAS", "AUDIO", "VIDEO", "OBJECT", "EMBED", "DIALOG",
  "HEADER", "NAV", "FOOTER", "ASIDE"
]);

/**
 * Class / ID substrings commonly indicating ads, navigation, social, comments, etc.
 * Handles space, hyphen, and underscore boundary delimiters across various CMS platforms.
 */
const JUNK_CLASS_REGEX = /(?:^|[\s_-])(header|masthead|navbar|nav|menu|breadcrumb|breadcrumbs|site-header|page-header|entry-header|post-header|article-header|top-bar|topbar|share|social|share-bar|social-share|share-buttons|clap|like|reaction|speechify|speech-player|audio-player|listen|bookmark|follow|author-card|author-info|author-bio|action-bar|post-actions|ad|advertisement|sponsored|promo|banner|popup|modal|cookie|paywall|subscribe|subscription|newsletter|outbrain|taboola|sidebar|widget|related|trending|popular|comments?|disqus|tags?|kicker|badge|open-in-app)(?:$|[\s_-])/i;

/**
 * Class / ID substrings indicating good article content containers.
 */
const CONTENT_CLASS_REGEX = /(?:^|[\s_-])(article-body|story-body|post-content|article-content|entry-content|main-content|prose|body-content|story-content)(?:$|[\s_-])/i;

/**
 * Extracts the primary content from an HTML string or document.
 * @param {string} html
 * @param {string} [baseUrl=""]
 * @param {{ mode?: "reader" | "full" }} [options={}]
 * @returns {{
 *   title: string,
 *   byline: string,
 *   siteName: string,
 *   publishedTime: string,
 *   leadImage: string,
 *   contentHtml: string,
 *   textContent: string,
 *   wordCount: number,
 *   readingTimeMinutes: number,
 *   url: string
 * }}
 */
export function extractPrimaryContent(html, baseUrl = "", options = {}) {
  const meta = extractMetadata(html, baseUrl);
  const mode = options.mode || "reader";

  const root = parseHTMLToTree(html);

  // 1. Remove obvious junk and structural tags
  for (const tag of JUNK_TAGS) {
    const junkElements = root.getElementsByTagName(tag);
    for (const el of junkElements) {
      el.remove();
    }
  }

  // If full mode requested, clean up body and return
  if (mode === "full") {
    const bodies = root.getElementsByTagName("body");
    const container = bodies.length > 0 ? bodies[0] : root;
    sanitizeElementTree(container, baseUrl);
    const textContent = container.textContent.trim();
    const stats = estimateReadingStats(textContent);
    return {
      ...meta,
      contentHtml: container.toHTML(),
      textContent,
      wordCount: stats.wordCount,
      readingTimeMinutes: stats.readingTimeMinutes,
      url: baseUrl
    };
  }

  // 2. Remove elements with non-article ARIA roles
  const junkRoles = new Set(["banner", "navigation", "complementary", "dialog", "alert", "search"]);
  const allRoleElements = root.getElementsByTagName("*");
  for (const el of allRoleElements) {
    const role = (el.getAttribute("role") || "").toLowerCase();
    if (junkRoles.has(role)) {
      el.remove();
    }
  }

  // 3. Remove elements matching junk classes/ids
  const allElements = root.getElementsByTagName("*");
  for (const el of allElements) {
    const cls = el.getAttribute("class") || "";
    const id = el.getAttribute("id") || "";
    const combined = `${cls} ${id}`;
    if (JUNK_CLASS_REGEX.test(combined) && !CONTENT_CLASS_REGEX.test(combined)) {
      el.remove();
    }
  }

  // 4. Find candidate content containers
  const candidateTags = ["ARTICLE", "SECTION", "MAIN", "DIV"];
  let bestNode = null;
  let bestScore = 0;

  for (const tag of candidateTags) {
    const candidates = root.getElementsByTagName(tag);
    for (const node of candidates) {
      const score = scoreCandidateNode(node);
      if (score > bestScore) {
        bestScore = score;
        bestNode = node;
      }
    }
  }

  // Refine container: if a child container holds >= 75% of parent paragraphs (e.g. story-body inside article),
  // prefer the child container to eliminate wrapper clutter
  if (bestNode) {
    let currentBest = bestNode;
    let refined = true;
    while (refined) {
      refined = false;
      const childCandidates = [...currentBest.children].filter(
        c => c.nodeType === 1 && ["ARTICLE", "SECTION", "DIV", "MAIN"].includes(c.tagName)
      );
      const parentPCount = currentBest.getElementsByTagName("P").length;
      for (const child of childCandidates) {
        const childPCount = child.getElementsByTagName("P").length;
        if (parentPCount >= 2 && childPCount >= Math.floor(parentPCount * 0.75)) {
          currentBest = child;
          refined = true;
          break;
        }
      }
    }
    bestNode = currentBest;
  }

  // Fallback to body or root only if no candidate found
  if (!bestNode) {
    const bodies = root.getElementsByTagName("body");
    bestNode = bodies.length > 0 ? bodies[0] : root;
  }

  // 5. Prune leading clutter & duplicate title
  pruneLeadingClutter(bestNode, meta.title);

  // 6. Sanitize and clean best node's children
  sanitizeElementTree(bestNode, baseUrl);

  const textContent = bestNode.textContent.trim();
  const stats = estimateReadingStats(textContent);

  return {
    ...meta,
    contentHtml: bestNode.toHTML(),
    textContent,
    wordCount: stats.wordCount,
    readingTimeMinutes: stats.readingTimeMinutes,
    url: baseUrl
  };
}

/**
 * Removes leading non-article elements (breadcrumbs, author cards, kickers)
 * and duplicate title headings before the main story text.
 * @param {MiniNode} node
 * @param {string} title
 */
function pruneLeadingClutter(node, title) {
  // 1. Remove duplicate h1 matching title
  const headings = node.getElementsByTagName("H1");
  if (headings.length > 0) {
    const firstH1 = headings[0];
    const h1Text = firstH1.textContent.trim().toLowerCase();
    const titleText = (title || "").trim().toLowerCase();
    if (h1Text && titleText && (h1Text === titleText || titleText.includes(h1Text) || h1Text.includes(titleText))) {
      firstH1.remove();
    }
  }

  // 2. Remove leading child elements before the first substantive paragraph or section heading
  const children = [...node.children];
  for (const child of children) {
    if (child.nodeType === 3 && !child.textValue.trim()) {
      child.remove();
      continue;
    }
    if (child.nodeType === 1) {
      if (child.tagName === "P" && child.textContent.trim().length > 30) {
        break; // Found start of primary story
      }
      if (["H2", "H3"].includes(child.tagName)) {
        break;
      }
      const pCount = child.getElementsByTagName("P").length;
      if (pCount === 0) {
        child.remove();
      } else {
        break;
      }
    }
  }
}

/**
 * Scores a candidate node for article likelihood.
 * @param {MiniNode} node
 * @returns {number}
 */
function scoreCandidateNode(node) {
  let score = 0;
  const pList = node.getElementsByTagName("P");
  const pCount = pList.length;

  if (pCount === 0) return 0;
  score += pCount * 30;

  const text = node.textContent.trim();
  const textLen = text.length;
  if (textLen < 100) return 0;
  score += Math.min(Math.floor(textLen / 80), 80);

  // Link density: ratio of text in <a> tags vs total text
  const links = node.getElementsByTagName("A");
  let linkTextLen = 0;
  for (const a of links) {
    linkTextLen += a.textContent.trim().length;
  }
  const linkDensity = textLen > 0 ? linkTextLen / textLen : 0;
  if (linkDensity > 0.45) {
    // Highly link-heavy (likely a nav or sidebar list)
    return 0;
  }
  score *= (1 - linkDensity);

  // Class/ID bonus & penalty
  const cls = (node.getAttribute("class") || "") + " " + (node.getAttribute("id") || "");
  if (CONTENT_CLASS_REGEX.test(cls)) score += 40;
  if (JUNK_CLASS_REGEX.test(cls)) score -= 40;

  return Math.max(0, score);
}

/**
 * Whitelist of allowed tags in the final cleaned article body.
 */
const ALLOWED_TAGS = new Set([
  "P", "H1", "H2", "H3", "H4", "H5", "H6", "IMG", "FIGURE", "FIGCAPTION",
  "UL", "OL", "LI", "BLOCKQUOTE", "PRE", "CODE", "A", "B", "STRONG", "I",
  "EM", "U", "MARK", "TABLE", "THEAD", "TBODY", "TR", "TH", "TD", "HR", "BR"
]);

/**
 * Sanitizes element tree: resolves URLs, strips dangerous/extraneous attributes,
 * and flattens or removes non-whitelisted tags.
 * @param {MiniNode} node
 * @param {string} baseUrl
 */
function sanitizeElementTree(node, baseUrl) {
  const traverse = (current) => {
    // Clone children array to allow safe modification during iteration
    const children = [...current.children];
    for (const child of children) {
      if (child.nodeType === 3) continue;

      if (!ALLOWED_TAGS.has(child.tagName)) {
        // Unwrap allowed children or remove
        const grandChildren = [...child.children];
        const idx = current.children.indexOf(child);
        if (idx !== -1) {
          current.children.splice(idx, 1);
          for (let i = 0; i < grandChildren.length; i++) {
            grandChildren[i].parentNode = current;
            current.children.splice(idx + i, 0, grandChildren[i]);
          }
        }
        for (const gc of grandChildren) {
          traverse(gc);
        }
        continue;
      }

      // Filter attributes: keep only essential safe attributes
      const allowedAttrs = new Set(["href", "src", "alt", "title", "target", "colspan", "rowspan"]);
      for (const attr of Object.keys(child.attrs)) {
        if (!allowedAttrs.has(attr)) {
          child.removeAttribute(attr);
        }
      }

      // Resolve relative URLs
      if (child.tagName === "IMG") {
        const src = child.getAttribute("src");
        if (src) {
          child.setAttribute("src", resolveUrl(src, baseUrl));
        }
      } else if (child.tagName === "A") {
        const href = child.getAttribute("href");
        if (href) {
          child.setAttribute("href", resolveUrl(href, baseUrl));
          child.setAttribute("target", "_blank");
        }
      }

      traverse(child);
    }
  };

  traverse(node);
}

/**
 * Constructs a print-ready HTML document string for WebKit PDF rendering.
 * @param {{
 *   title: string,
 *   byline: string,
 *   siteName: string,
 *   publishedTime: string,
 *   leadImage: string,
 *   contentHtml: string,
 *   wordCount: number,
 *   readingTimeMinutes: number,
 *   url: string
 * }} article
 * @param {{ paperSize?: "A4" | "Letter" }} [options={}]
 * @returns {string} Complete HTML document
 */
export function buildPrintableHtml(article, options = {}) {
  const paperSize = options.paperSize || "A4";
  const title = article.title || "Untitled Article";
  const domain = article.siteName || getDomainFromUrl(article.url);
  const byline = article.byline ? `By ${article.byline}` : "";
  const dateStr = article.publishedTime ? new Date(article.publishedTime).toLocaleDateString(undefined, { year: "numeric", month: "short", day: "numeric" }) : "";
  const statsStr = article.wordCount ? `${article.readingTimeMinutes} min read • ${article.wordCount} words` : "";

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>${escapeHtml(title)}</title>
  <style>
    @page {
      size: ${paperSize};
      margin: 20mm 18mm 22mm 18mm;
      @bottom-right {
        content: counter(page);
        font-size: 8.5pt;
        color: #888;
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
      }
    }
    *, *::before, *::after {
      box-sizing: border-box;
    }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
      color: #1a1a1a;
      background: #ffffff;
      line-height: 1.68;
      font-size: 11pt;
      margin: 0;
      padding: 0;
      -webkit-font-smoothing: antialiased;
      word-wrap: break-word;
    }
    .reader-article {
      max-width: 100%;
      margin: 0 auto;
    }
    .reader-header {
      border-bottom: 2px solid #e5e7eb;
      padding-bottom: 16px;
      margin-bottom: 24px;
    }
    .reader-site-name {
      font-size: 9.5pt;
      text-transform: uppercase;
      letter-spacing: 0.08em;
      color: #6b7280;
      font-weight: 600;
      margin-bottom: 8px;
    }
    .reader-title {
      font-size: 24pt;
      font-weight: 700;
      line-height: 1.25;
      color: #111827;
      margin: 0 0 14px 0;
    }
    .reader-meta {
      display: flex;
      flex-wrap: wrap;
      gap: 12px;
      font-size: 9pt;
      color: #6b7280;
    }
    .reader-meta span:not(:last-child)::after {
      content: "•";
      margin-left: 12px;
      color: #9ca3af;
    }
    .reader-lead-image {
      margin: 20px 0 24px 0;
      text-align: center;
    }
    .reader-lead-image img {
      max-width: 100%;
      height: auto;
      border-radius: 6px;
      max-height: 380px;
      object-fit: cover;
    }
    .reader-body {
      font-size: 11pt;
      line-height: 1.7;
      color: #27272a;
    }
    .reader-body p {
      margin: 0 0 1.25em 0;
      text-align: justify;
      hyphens: auto;
    }
    .reader-body h1, .reader-body h2, .reader-body h3, .reader-body h4 {
      color: #0f172a;
      margin: 1.5em 0 0.6em 0;
      line-height: 1.3;
      page-break-after: avoid;
      break-after: avoid;
    }
    .reader-body h1 { font-size: 16pt; }
    .reader-body h2 { font-size: 14pt; }
    .reader-body h3 { font-size: 12pt; }
    .reader-body img {
      max-width: 100%;
      height: auto;
      margin: 1.2em 0;
      border-radius: 4px;
      page-break-inside: avoid;
      break-inside: avoid;
    }
    .reader-body blockquote {
      border-left: 4px solid #3b82f6;
      margin: 1.4em 0;
      padding: 0.6em 1.2em;
      color: #4b5563;
      background: #f8fafc;
      font-style: italic;
      page-break-inside: avoid;
      break-inside: avoid;
    }
    .reader-body pre {
      background: #f1f5f9;
      padding: 12px 16px;
      border-radius: 6px;
      font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
      font-size: 9.5pt;
      overflow-x: auto;
      page-break-inside: avoid;
      break-inside: avoid;
    }
    .reader-body code {
      font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
      background: #f1f5f9;
      padding: 2px 5px;
      border-radius: 3px;
      font-size: 9.5pt;
    }
    .reader-body ul, .reader-body ol {
      margin: 0 0 1.25em 0;
      padding-left: 1.8em;
    }
    .reader-body li {
      margin-bottom: 0.4em;
    }
    .reader-body table {
      width: 100%;
      border-collapse: collapse;
      margin: 1.5em 0;
      font-size: 9.5pt;
      page-break-inside: avoid;
      break-inside: avoid;
    }
    .reader-body th, .reader-body td {
      border: 1px solid #e2e8f0;
      padding: 8px 12px;
      text-align: left;
    }
    .reader-body th {
      background: #f8fafc;
      font-weight: 600;
    }
    .reader-body a {
      color: #2563eb;
      text-decoration: underline;
    }
    .reader-footer {
      margin-top: 36px;
      padding-top: 14px;
      border-top: 1px solid #e5e7eb;
      font-size: 8.5pt;
      color: #9ca3af;
      display: flex;
      justify-content: space-between;
    }
  </style>
</head>
<body>
  <article class="reader-article">
    <header class="reader-header">
      ${domain ? `<div class="reader-site-name">${escapeHtml(domain)}</div>` : ""}
      <h1 class="reader-title">${escapeHtml(title)}</h1>
      <div class="reader-meta">
        ${byline ? `<span>${escapeHtml(byline)}</span>` : ""}
        ${dateStr ? `<span>${escapeHtml(dateStr)}</span>` : ""}
        ${statsStr ? `<span>${escapeHtml(statsStr)}</span>` : ""}
      </div>
    </header>
    ${article.leadImage ? `<div class="reader-lead-image"><img src="${escapeHtml(article.leadImage)}" alt="Article lead image"></div>` : ""}
    <div class="reader-body">
      ${article.contentHtml}
    </div>
    <footer class="reader-footer">
      <span>Downloaded from ${escapeHtml(article.url || domain)}</span>
      <span>Rendered with Bag of Utils</span>
    </footer>
  </article>
</body>
</html>`;
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
