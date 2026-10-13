import { test } from "node:test";
import assert from "node:assert";
import {
  SUPPORTED_FORMATS,
  detectFormat,
  isSupportedDocument,
  getTargetFileName,
  generateConversionPreview
} from "../src/web/converter.js";

test("detectFormat - recognises supported formats and aliases (case-insensitive)", () => {
  assert.strictEqual(detectFormat("book.pdf"), "pdf");
  assert.strictEqual(detectFormat("Book.EPUB"), "epub");
  assert.strictEqual(detectFormat("scan.djvu"), "djvu");
  assert.strictEqual(detectFormat("scan.djv"), "djvu");
  assert.strictEqual(detectFormat("page.htm"), "html");
  assert.strictEqual(detectFormat("notes.markdown"), "md");
  assert.strictEqual(detectFormat("letter.docx"), "docx");
  assert.strictEqual(detectFormat("a.b.c.txt"), "txt");
});

test("detectFormat - rejects unsupported, hidden and extensionless names", () => {
  assert.strictEqual(detectFormat("photo.jpg"), null);
  assert.strictEqual(detectFormat("README"), null);
  assert.strictEqual(detectFormat(".pdf"), null);
  assert.strictEqual(detectFormat(""), null);
  assert.strictEqual(detectFormat(null), null);
});

test("isSupportedDocument - ignores directories", () => {
  assert.strictEqual(isSupportedDocument("book.pdf", false), true);
  assert.strictEqual(isSupportedDocument("folder.pdf", true), false);
  assert.strictEqual(isSupportedDocument("image.png", false), false);
});

test("getTargetFileName - swaps extension and supports suffix", () => {
  assert.strictEqual(getTargetFileName("My Book.epub", "pdf"), "My Book.pdf");
  assert.strictEqual(getTargetFileName("a.b.djvu", "txt", "_converted"), "a.b_converted.txt");
  assert.throws(() => getTargetFileName("a.pdf", "exe"), /Unsupported target format/);
});

test("SUPPORTED_FORMATS - every format has a unique id and extension", () => {
  const ids = new Set(SUPPORTED_FORMATS.map(f => f.id));
  const exts = new Set(SUPPORTED_FORMATS.map(f => f.ext));
  assert.strictEqual(ids.size, SUPPORTED_FORMATS.length);
  assert.strictEqual(exts.size, SUPPORTED_FORMATS.length);
});

const dir = "/docs";
const file = (name, size = 100, directory = dir) => ({ name, size, directory, path: `${directory}/${name}` });

test("generateConversionPreview - filters unsupported files and sorts naturally", () => {
  const res = generateConversionPreview(
    [file("b10.epub"), file("b2.epub"), file("pic.png"), { name: "sub.pdf", isDirectory: true, size: 0, directory: dir }],
    { targetFormat: "pdf" }
  );
  assert.deepEqual(res.map(r => r.originalName), ["b2.epub", "b10.epub"]);
  assert.strictEqual(res[0].targetName, "b2.pdf");
  assert.strictEqual(res[0].targetPath, "/docs/b2.pdf");
  assert.strictEqual(res[0].status, "ready");
  assert.strictEqual(res[0].willConvert, true);
});

test("generateConversionPreview - applies source format filter", () => {
  const res = generateConversionPreview(
    [file("a.epub"), file("b.djvu"), file("c.pdf")],
    { targetFormat: "txt", sourceFormatFilter: "djvu" }
  );
  assert.strictEqual(res.length, 1);
  assert.strictEqual(res[0].originalName, "b.djvu");
});

test("generateConversionPreview - same-format files are not converted", () => {
  const res = generateConversionPreview([file("a.pdf")], { targetFormat: "pdf" });
  assert.strictEqual(res[0].isSameFormat, true);
  assert.strictEqual(res[0].willConvert, false);
  assert.strictEqual(res[0].status, "same_format");
});

test("generateConversionPreview - rename mode avoids overwriting existing outputs", () => {
  const files = [file("book.epub"), file("book.pdf")];
  const res = generateConversionPreview(files, { targetFormat: "pdf", conflictAction: "rename" });
  const epub = res.find(r => r.originalName === "book.epub");
  assert.strictEqual(epub.targetName, "book_converted.pdf");
  assert.strictEqual(epub.willConvert, true);
});

test("generateConversionPreview - rename mode increments suffix when needed", () => {
  const res = generateConversionPreview([file("book.epub")], {
    targetFormat: "pdf",
    existingTargetFiles: ["/docs/book.pdf", "/docs/book_converted.pdf"]
  });
  assert.strictEqual(res[0].targetName, "book_converted_2.pdf");
});

test("generateConversionPreview - skip mode skips existing outputs", () => {
  const res = generateConversionPreview([file("book.epub"), file("book.pdf")], {
    targetFormat: "pdf",
    conflictAction: "skip"
  });
  const epub = res.find(r => r.originalName === "book.epub");
  assert.strictEqual(epub.isSkipped, true);
  assert.strictEqual(epub.willConvert, false);
  assert.strictEqual(epub.status, "skipped");
});

test("generateConversionPreview - overwrite mode keeps the natural target name", () => {
  const res = generateConversionPreview([file("book.epub"), file("book.pdf")], {
    targetFormat: "pdf",
    conflictAction: "overwrite"
  });
  const epub = res.find(r => r.originalName === "book.epub");
  assert.strictEqual(epub.targetName, "book.pdf");
  assert.strictEqual(epub.willConvert, true);
});

test("generateConversionPreview - rename mode disambiguates batch duplicates", () => {
  const res = generateConversionPreview([file("book.epub"), file("book.djvu")], {
    targetFormat: "pdf",
    conflictAction: "rename"
  });
  const names = res.map(r => r.targetName).sort();
  assert.deepEqual(names, ["book.pdf", "book_converted.pdf"]);
  assert.ok(res.every(r => r.willConvert));
});

test("generateConversionPreview - overwrite mode flags batch duplicates as conflicts", () => {
  const res = generateConversionPreview([file("book.epub"), file("book.djvu")], {
    targetFormat: "pdf",
    conflictAction: "overwrite"
  });
  assert.ok(res.every(r => r.conflict && !r.willConvert && r.status === "conflict"));
  assert.match(res[0].conflictReason, /Duplicate output filename/);
});

test("generateConversionPreview - same names in different directories do not collide", () => {
  const res = generateConversionPreview(
    [file("book.epub", 1, "/a"), file("book.djvu", 1, "/b")],
    { targetFormat: "pdf", conflictAction: "overwrite" }
  );
  assert.ok(res.every(r => !r.conflict && r.willConvert));
});

test("generateConversionPreview - custom output directory is honoured", () => {
  const res = generateConversionPreview([file("book.epub")], {
    targetFormat: "txt",
    outputDirectory: "/out",
    existingTargetFiles: ["/out/book.txt"]
  });
  assert.strictEqual(res[0].targetDirectory, "/out");
  assert.strictEqual(res[0].targetName, "book_converted.txt");
  assert.strictEqual(res[0].targetPath, "/out/book_converted.txt");
});

test("generateConversionPreview - throws on invalid options", () => {
  assert.throws(() => generateConversionPreview([], { targetFormat: "exe" }), /Unsupported target format/);
  assert.throws(() => generateConversionPreview([], { conflictAction: "explode" }), /Unsupported conflict action/);
});

test("generateConversionPreview - handles empty input", () => {
  assert.deepEqual(generateConversionPreview([], { targetFormat: "pdf" }), []);
  assert.deepEqual(generateConversionPreview(null, { targetFormat: "pdf" }), []);
});
