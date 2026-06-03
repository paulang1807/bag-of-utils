/**
 * Helper to split a filename into name and extension.
 * Directories and hidden files are treated specially.
 * @param {string} filename 
 * @param {boolean} isDirectory 
 * @returns {{name: string, ext: string}}
 */
export function getFileParts(filename, isDirectory) {
  if (isDirectory) {
    return { name: filename, ext: "" };
  }
  
  // Handle hidden files (e.g. .gitignore) which shouldn't have their name removed
  if (filename.startsWith(".") && filename.indexOf(".", 1) === -1) {
    return { name: filename, ext: "" };
  }
  
  const lastDot = filename.lastIndexOf(".");
  if (lastDot <= 0) {
    return { name: filename, ext: "" };
  }
  
  return {
    name: filename.slice(0, lastDot),
    ext: filename.slice(lastDot)
  };
}

/**
 * Generates a preview list of old and new filenames based on renaming configuration.
 * Detects conflicts (e.g. name collisions).
 * 
 * @param {Array<{name: string, isDirectory: boolean, size: number}>} files 
 * @param {{prefix: string, format: string, startIndex: number, padding: number}} options 
 * @returns {Array<{originalName: string, newName: string, isDirectory: boolean, size: number, isUnchanged: boolean, conflict: boolean, conflictReason: string}>}
 */
export function generatePreview(files, options = {}) {
  const {
    prefix = "",
    format = "prefix_number",
    startIndex = 1,
    padding = 3
  } = options;

  // Validation: prefix cannot contain character '/' or ':' (macOS directory/file naming limits)
  const invalidChars = /[\/:]/;
  if (invalidChars.test(prefix)) {
    throw new Error("Prefix cannot contain illegal characters: '/' or ':'");
  }

  const results = [];
  const targetNamesCount = new Map();

  // Sort files deterministically (case-insensitive natural sort)
  const sortedFiles = [...files].sort((a, b) => 
    a.name.localeCompare(undefined, { numeric: true, sensitivity: "base" })
  );

  let counter = startIndex;

  for (const file of sortedFiles) {
    const { name: originalName, ext } = getFileParts(file.name, file.isDirectory);
    let newName = "";

    switch (format) {
      case "prefix_number": {
        const paddedNum = String(counter).padStart(padding, "0");
        newName = `${prefix}_${paddedNum}${ext}`;
        counter++;
        break;
      }
      case "prefix_dash_number": {
        const paddedNum = String(counter).padStart(padding, "0");
        newName = `${prefix}-${paddedNum}${ext}`;
        counter++;
        break;
      }
      case "prefix_space_number": {
        const paddedNum = String(counter).padStart(padding, "0");
        newName = `${prefix} ${paddedNum}${ext}`;
        counter++;
        break;
      }
      case "prefix_original": {
        // Fallback to original name if prefix is empty, otherwise prepend prefix_
        newName = prefix ? `${prefix}_${originalName}${ext}` : `${originalName}${ext}`;
        break;
      }
      default:
        throw new Error(`Unsupported renaming format: ${format}`);
    }

    const isUnchanged = file.name === newName;

    results.push({
      originalName: file.name,
      newName,
      isDirectory: file.isDirectory,
      size: file.size,
      isUnchanged,
      conflict: false,
      conflictReason: ""
    });

    targetNamesCount.set(newName, (targetNamesCount.get(newName) || 0) + 1);
  }

  // Identify duplicate target conflicts
  for (const item of results) {
    if ((targetNamesCount.get(item.newName) || 0) > 1) {
      item.conflict = true;
      item.conflictReason = `Duplicate destination name: '${item.newName}' will be generated multiple times.`;
    }
  }

  return results;
}
