import { getFileParts } from "./renamer.js";

/**
 * Supported document formats for conversion.
 */
export const SUPPORTED_FORMATS = [
  { id: "pdf", label: "PDF Document", ext: ".pdf", aliases: [".pdf"] },
  { id: "epub", label: "EPUB E-Book", ext: ".epub", aliases: [".epub"] },
  { id: "djvu", label: "DjVu Document", ext: ".djvu", aliases: [".djvu", ".djv"] },
  { id: "docx", label: "Word Document (DOCX)", ext: ".docx", aliases: [".docx"] },
  { id: "html", label: "HTML Document", ext: ".html", aliases: [".html", ".htm"] },
  { id: "txt", label: "Plain Text", ext: ".txt", aliases: [".txt", ".text"] },
  { id: "rtf", label: "Rich Text Format (RTF)", ext: ".rtf", aliases: [".rtf"] },
  { id: "md", label: "Markdown", ext: ".md", aliases: [".md", ".markdown"] }
];

const EXTENSION_TO_FORMAT = new Map();
for (const fmt of SUPPORTED_FORMATS) {
  for (const alias of fmt.aliases) {
    EXTENSION_TO_FORMAT.set(alias.toLowerCase(), fmt.id);
  }
}

/**
 * Detects the normalized document format ID from a filename.
 * @param {string} filename
 * @returns {string|null} Format ID (e.g. "pdf", "epub", "djvu") or null if unsupported
 */
export function detectFormat(filename) {
  if (!filename || typeof filename !== "string") return null;
  const { ext } = getFileParts(filename, false);
  if (!ext) return null;
  return EXTENSION_TO_FORMAT.get(ext.toLowerCase()) || null;
}

/**
 * Checks whether a file entry is a supported document for conversion.
 * @param {string} filename
 * @param {boolean} isDirectory
 * @returns {boolean}
 */
export function isSupportedDocument(filename, isDirectory = false) {
  if (isDirectory) return false;
  return detectFormat(filename) !== null;
}

/**
 * Constructs a target filename for a given source filename and target format.
 * @param {string} filename
 * @param {string} targetFormat
 * @param {string} [suffix=""]
 * @returns {string}
 */
export function getTargetFileName(filename, targetFormat, suffix = "") {
  const fmt = SUPPORTED_FORMATS.find(f => f.id === targetFormat);
  if (!fmt) {
    throw new Error(`Unsupported target format: ${targetFormat}`);
  }
  const { name } = getFileParts(filename, false);
  return `${name}${suffix}${fmt.ext}`;
}

/**
 * Generates a live conversion preview list from input files and options.
 *
 * @param {Array<{name: string, size: number, isDirectory?: boolean, path?: string, directory?: string}>} files
 * @param {{
 *   targetFormat?: string,
 *   sourceFormatFilter?: string,
 *   conflictAction?: "rename" | "skip" | "overwrite",
 *   outputDirectory?: string | null,
 *   existingTargetFiles?: Array<string> | Set<string> | null
 * }} options
 * @returns {Array<{
 *   originalName: string,
 *   sourcePath: string | null,
 *   sourceDirectory: string | null,
 *   sourceFormat: string,
 *   targetFormat: string,
 *   targetName: string,
 *   targetDirectory: string | null,
 *   targetPath: string | null,
 *   size: number,
 *   isSameFormat: boolean,
 *   isSkipped: boolean,
 *   conflict: boolean,
 *   conflictReason: string,
 *   willConvert: boolean,
 *   status: "ready" | "same_format" | "skipped" | "conflict"
 * }>}
 */
export function generateConversionPreview(files, options = {}) {
  const {
    targetFormat = "pdf",
    sourceFormatFilter = "all",
    conflictAction = "rename",
    outputDirectory = null,
    existingTargetFiles = null
  } = options;

  if (!SUPPORTED_FORMATS.some(f => f.id === targetFormat)) {
    throw new Error(`Unsupported target format: ${targetFormat}`);
  }

  if (!["rename", "skip", "overwrite"].includes(conflictAction)) {
    throw new Error(`Unsupported conflict action: ${conflictAction}`);
  }

  // Filter to supported documents and apply sourceFormatFilter if specified
  const validDocs = (files || []).filter(file => {
    if (!isSupportedDocument(file.name, Boolean(file.isDirectory))) {
      return false;
    }
    const fmt = detectFormat(file.name);
    if (sourceFormatFilter && sourceFormatFilter !== "all" && fmt !== sourceFormatFilter) {
      return false;
    }
    return true;
  });

  // Sort deterministically (case-insensitive natural sort)
  const sortedDocs = [...validDocs].sort((a, b) =>
    a.name.localeCompare(b.name, undefined, { numeric: true, sensitivity: "base" })
  );

  // Collision keys are full paths (lowercased: default macOS APFS is case-insensitive),
  // so identically named outputs in different directories never collide.
  const keyOf = (dir, name) => `${dir || ""}/${name}`.toLowerCase();

  const existingSet = new Set();
  if (existingTargetFiles) {
    for (const p of existingTargetFiles) {
      existingSet.add(String(p).toLowerCase());
    }
  } else {
    for (const f of files || []) {
      if (f && f.name) {
        const d = f.directory || (f.path ? f.path.slice(0, f.path.lastIndexOf("/")) : null);
        existingSet.add(keyOf(d, f.name));
      }
    }
  }

  const batchAllocatedLower = new Set();
  const targetNamesCount = new Map();
  const results = [];

  for (const file of sortedDocs) {
    const sourceFormat = detectFormat(file.name);
    const isSameFormat = sourceFormat === targetFormat;
    const sourceDirectory = file.directory || (file.path ? file.path.slice(0, file.path.lastIndexOf("/")) : null);
    const sourcePath = file.path || (sourceDirectory ? `${sourceDirectory}/${file.name}` : null);
    const targetDir = outputDirectory || sourceDirectory || null;

    let targetName = getTargetFileName(file.name, targetFormat);
    let isSkipped = false;
    let conflict = false;
    let conflictReason = "";

    if (!isSameFormat) {
      const initialKey = keyOf(targetDir, targetName);
      const existsOnDisk = existingSet.has(initialKey);
      const existsInBatch = batchAllocatedLower.has(initialKey);

      if (conflictAction === "rename") {
        if (existsOnDisk || existsInBatch) {
          let attempt = 1;
          let candidate = getTargetFileName(file.name, targetFormat, "_converted");
          while (
            existingSet.has(keyOf(targetDir, candidate)) ||
            batchAllocatedLower.has(keyOf(targetDir, candidate))
          ) {
            attempt++;
            candidate = getTargetFileName(file.name, targetFormat, `_converted_${attempt}`);
          }
          targetName = candidate;
        }
      } else if (conflictAction === "skip") {
        if (existsOnDisk) {
          isSkipped = true;
          conflictReason = `Target '${targetName}' already exists and will be skipped.`;
        }
      }
    }

    const finalKey = keyOf(targetDir, targetName);
    batchAllocatedLower.add(finalKey);

    if (!isSameFormat && !isSkipped) {
      targetNamesCount.set(finalKey, (targetNamesCount.get(finalKey) || 0) + 1);
    }

    const targetPath = targetDir ? `${targetDir}/${targetName}` : null;

    results.push({
      originalName: file.name,
      sourcePath,
      sourceDirectory,
      sourceFormat,
      targetFormat,
      targetName,
      targetDirectory: targetDir,
      targetPath,
      size: file.size || 0,
      isSameFormat,
      isSkipped,
      conflict,
      conflictReason,
      willConvert: !isSameFormat && !isSkipped && !conflict,
      status: isSameFormat ? "same_format" : isSkipped ? "skipped" : "ready"
    });
  }

  // Flag duplicate target names within the same batch (e.g. book.epub and book.djvu both converting to book.pdf under overwrite/skip mode)
  for (const item of results) {
    if (!item.isSameFormat && !item.isSkipped) {
      const count = targetNamesCount.get(keyOf(item.targetDirectory, item.targetName)) || 0;
      if (count > 1) {
        item.conflict = true;
        item.willConvert = false;
        item.status = "conflict";
        item.conflictReason = `Duplicate output filename in batch: '${item.targetName}' would be written by multiple source files.`;
      }
    }
  }

  return results;
}
